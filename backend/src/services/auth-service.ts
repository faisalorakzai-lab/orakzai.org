import { randomUUID } from "node:crypto";

import type { PoolClient } from "pg";

import { config } from "../config.js";
import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { assertEmailDeliveryAvailable, sendAuthCode } from "../mailer.js";
import {
  createAccessToken,
  createOneTimeCode,
  createRefreshToken,
  hashOpaqueToken,
  hashPassword,
  normalizeEmail,
  normalizePhone,
  safeEqualHex,
  verifyPassword,
} from "../security.js";

export type RegisterInput = {
  fullName: string;
  email: string;
  phone: string;
  password: string;
};

export type TokenPair = {
  accessToken: string;
  refreshToken: string;
  tokenType: "Bearer";
  expiresIn: number;
};

async function withTransaction<T>(run: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await run(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function recordAudit(
  client: PoolClient,
  actorId: string | null,
  action: string,
  entityId: string | null,
): Promise<void> {
  await client.query(
    `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id)
     VALUES ($1, $2, $3, $4)`,
    [actorId, action, entityId ? "user" : null, entityId],
  );
}

function tokenPair(userId: string, sessionId: string, refreshToken: string): TokenPair {
  return {
    accessToken: createAccessToken(userId, sessionId),
    refreshToken,
    tokenType: "Bearer",
    expiresIn: config.accessTokenTtlSeconds,
  };
}

export async function register(input: RegisterInput): Promise<{
  message: string;
  devVerificationCode?: string;
}> {
  assertEmailDeliveryAvailable();
  const email = normalizeEmail(input.email);
  const phone = normalizePhone(input.phone);
  const passwordHash = await hashPassword(input.password);
  const userId = randomUUID();
  const code = createOneTimeCode();

  await withTransaction(async (client) => {
    try {
      await client.query(
        `INSERT INTO users (id, email, phone, password_hash)
         VALUES ($1, $2, $3, $4)`,
        [userId, email, phone, passwordHash],
      );
    } catch (error) {
      if (
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        error.code === "23505"
      ) {
        throw new HttpError(409, "ACCOUNT_EXISTS", "An account already uses those details.");
      }
      throw error;
    }

    await client.query(
      `INSERT INTO user_profiles (user_id, full_name)
       VALUES ($1, $2)`,
      [userId, input.fullName.trim()],
    );
    await client.query(
      `INSERT INTO user_roles (user_id, role_id)
       SELECT $1, id FROM roles WHERE slug = 'standard_member'`,
      [userId],
    );
    await client.query(
      `INSERT INTO verification_requests
         (user_id, request_type, token_hash, expires_at)
       VALUES ($1, 'email_verification', $2, now() + ($3 * interval '1 minute'))`,
      [userId, hashOpaqueToken(code), config.verificationCodeMinutes],
    );
    await recordAudit(client, userId, "auth.registered", userId);
  });

  await sendAuthCode(email, code, "verify your email");
  return {
    message: "Account created. Verify your email before signing in.",
    ...(config.authDevMode ? { devVerificationCode: code } : {}),
  };
}

export async function verifyEmail(emailValue: string, codeValue: string): Promise<void> {
  const email = normalizeEmail(emailValue);
  const verified = await withTransaction(async (client) => {
    const result = await client.query<{
      user_id: string;
      verification_id: string;
      token_hash: string;
      attempt_count: number;
      expires_at: Date;
    }>(
      `SELECT u.id AS user_id, v.id AS verification_id, v.token_hash,
              v.attempt_count, v.expires_at
       FROM users u
       JOIN verification_requests v ON v.user_id = u.id
       WHERE u.email = $1
         AND v.request_type = 'email_verification'
         AND v.consumed_at IS NULL
       ORDER BY v.created_at DESC
       LIMIT 1
       FOR UPDATE OF v`,
      [email],
    );
    const request = result.rows[0];
    if (!request) return false;

    await client.query(
      "UPDATE verification_requests SET attempt_count = attempt_count + 1 WHERE id = $1",
      [request.verification_id],
    );
    if (
      request.expires_at.getTime() <= Date.now() ||
      request.attempt_count >= config.maxVerificationAttempts ||
      !safeEqualHex(request.token_hash, hashOpaqueToken(codeValue))
    ) {
      return false;
    }

    await client.query(
      `UPDATE verification_requests SET consumed_at = now()
       WHERE id = $1`,
      [request.verification_id],
    );
    await client.query(
      `UPDATE users
       SET email_verified_at = now(), account_status = 'active', updated_at = now()
       WHERE id = $1`,
      [request.user_id],
    );
    await recordAudit(client, request.user_id, "auth.email_verified", request.user_id);
    return true;
  });
  if (!verified) {
    throw new HttpError(400, "INVALID_VERIFICATION_CODE", "The code is invalid or expired.");
  }
}

export async function resendEmailVerification(emailValue: string): Promise<{
  message: string;
  devVerificationCode?: string;
}> {
  assertEmailDeliveryAvailable();
  const email = normalizeEmail(emailValue);
  const result = await pool.query<{ id: string }>(
    `SELECT id FROM users
     WHERE email = $1
       AND email_verified_at IS NULL
       AND account_status = 'pending'
     LIMIT 1`,
    [email],
  );
  const user = result.rows[0];
  if (!user) {
    return { message: "If the account needs verification, a code will be sent." };
  }

  const code = createOneTimeCode();
  await pool.query(
    `INSERT INTO verification_requests
       (user_id, request_type, token_hash, expires_at)
     VALUES ($1, 'email_verification', $2, now() + ($3 * interval '1 minute'))`,
    [user.id, hashOpaqueToken(code), config.verificationCodeMinutes],
  );
  await sendAuthCode(email, code, "verify your email");
  return {
    message: "If the account needs verification, a code will be sent.",
    ...(config.authDevMode ? { devVerificationCode: code } : {}),
  };
}

export async function login(identifierValue: string, password: string): Promise<TokenPair> {
  const identifier = identifierValue.trim();
  const email = identifier.includes("@") ? normalizeEmail(identifier) : null;
  const phone = email ? null : normalizePhone(identifier);
  const result = await pool.query<{
    id: string;
    password_hash: string;
    email_verified_at: Date | null;
    account_status: string;
  }>(
    `SELECT id, password_hash, email_verified_at, account_status
     FROM users
     WHERE ($1::text IS NOT NULL AND email = $1)
        OR ($2::text IS NOT NULL AND phone = $2)
     LIMIT 1`,
    [email, phone],
  );
  const user = result.rows[0];
  if (!user) {
    await verifyPassword(password, "$2b$12$4VE9Czk6B/0u0GrmSx9Q6u6b.Xf.XwS0jYVsr/Q8YZN5OfbpB6U9m");
    throw new HttpError(401, "INVALID_CREDENTIALS", "Email/phone or password is incorrect.");
  }
  if (!(await verifyPassword(password, user.password_hash))) {
    throw new HttpError(401, "INVALID_CREDENTIALS", "Email/phone or password is incorrect.");
  }
  if (!user.email_verified_at || user.account_status !== "active") {
    throw new HttpError(
      403,
      "EMAIL_NOT_VERIFIED",
      "Verify your email before signing in.",
    );
  }

  const sessionId = randomUUID();
  const refreshToken = createRefreshToken();
  await pool.query(
    `INSERT INTO user_sessions (id, user_id, refresh_token_hash, expires_at)
     VALUES ($1, $2, $3, now() + ($4 * interval '1 day'))`,
    [sessionId, user.id, hashOpaqueToken(refreshToken), config.refreshTokenDays],
  );
  await pool.query(
    "INSERT INTO audit_logs (actor_id, action, entity_type, entity_id) VALUES ($1, $2, 'session', $3)",
    [user.id, "auth.login", sessionId],
  );
  return tokenPair(user.id, sessionId, refreshToken);
}

export async function refresh(refreshTokenValue: string): Promise<TokenPair> {
  const oldHash = hashOpaqueToken(refreshTokenValue);
  const newRefreshToken = createRefreshToken();
  const newHash = hashOpaqueToken(newRefreshToken);

  const session = await withTransaction(async (client) => {
    const result = await client.query<{
      id: string;
      user_id: string;
      email_verified_at: Date | null;
      account_status: string;
    }>(
      `SELECT s.id, s.user_id, u.email_verified_at, u.account_status
       FROM user_sessions s
       JOIN users u ON u.id = s.user_id
       WHERE s.refresh_token_hash = $1
         AND s.revoked_at IS NULL
         AND s.expires_at > now()
       FOR UPDATE OF s`,
      [oldHash],
    );
    const active = result.rows[0];
    if (!active || !active.email_verified_at || active.account_status !== "active") {
      throw new HttpError(401, "INVALID_REFRESH_TOKEN", "Please sign in again.");
    }
    await client.query(
      `UPDATE user_sessions
       SET refresh_token_hash = $1,
           expires_at = now() + ($2 * interval '1 day'),
           last_used_at = now()
       WHERE id = $3`,
      [newHash, config.refreshTokenDays, active.id],
    );
    return { userId: active.user_id, sessionId: active.id };
  });

  return tokenPair(session.userId, session.sessionId, newRefreshToken);
}

export async function logout(sessionId: string, userId: string): Promise<void> {
  await pool.query(
    `UPDATE user_sessions SET revoked_at = now()
     WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
    [sessionId, userId],
  );
  await pool.query(
    "INSERT INTO audit_logs (actor_id, action, entity_type, entity_id) VALUES ($1, 'auth.logout', 'session', $2)",
    [userId, sessionId],
  );
}

export async function requestPasswordReset(emailValue: string): Promise<{
  message: string;
  devResetCode?: string;
}> {
  assertEmailDeliveryAvailable();
  const email = normalizeEmail(emailValue);
  const user = await pool.query<{ id: string; account_status: string }>(
    "SELECT id, account_status FROM users WHERE email = $1 LIMIT 1",
    [email],
  );
  const record = user.rows[0];
  if (!record || record.account_status !== "active") {
    return { message: "If an account matches, a reset code will be sent." };
  }

  const code = createOneTimeCode();
  await pool.query(
    `INSERT INTO verification_requests
       (user_id, request_type, token_hash, expires_at)
     VALUES ($1, 'password_reset', $2, now() + ($3 * interval '1 minute'))`,
    [record.id, hashOpaqueToken(code), config.verificationCodeMinutes],
  );
  await sendAuthCode(email, code, "reset your password");
  return {
    message: "If an account matches, a reset code will be sent.",
    ...(config.authDevMode ? { devResetCode: code } : {}),
  };
}

export async function resetPassword(
  emailValue: string,
  codeValue: string,
  newPassword: string,
): Promise<void> {
  const email = normalizeEmail(emailValue);
  const newHash = await hashPassword(newPassword);
  const reset = await withTransaction(async (client) => {
    const result = await client.query<{
      user_id: string;
      verification_id: string;
      token_hash: string;
      attempt_count: number;
      expires_at: Date;
    }>(
      `SELECT u.id AS user_id, v.id AS verification_id, v.token_hash,
              v.attempt_count, v.expires_at
       FROM users u
       JOIN verification_requests v ON v.user_id = u.id
       WHERE u.email = $1
         AND v.request_type = 'password_reset'
         AND v.consumed_at IS NULL
       ORDER BY v.created_at DESC
       LIMIT 1
       FOR UPDATE OF v`,
      [email],
    );
    const request = result.rows[0];
    if (!request) return false;
    await client.query(
      "UPDATE verification_requests SET attempt_count = attempt_count + 1 WHERE id = $1",
      [request.verification_id],
    );
    if (
      request.expires_at.getTime() <= Date.now() ||
      request.attempt_count >= config.maxVerificationAttempts ||
      !safeEqualHex(request.token_hash, hashOpaqueToken(codeValue))
    ) {
      return false;
    }

    await client.query(
      "UPDATE verification_requests SET consumed_at = now() WHERE id = $1",
      [request.verification_id],
    );
    await client.query(
      "UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2",
      [newHash, request.user_id],
    );
    await client.query(
      "UPDATE user_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL",
      [request.user_id],
    );
    await recordAudit(client, request.user_id, "auth.password_reset", request.user_id);
    return true;
  });
  if (!reset) {
    throw new HttpError(400, "INVALID_RESET_CODE", "The code is invalid or expired.");
  }
}
