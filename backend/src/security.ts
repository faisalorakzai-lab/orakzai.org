import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";

import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";

import { config } from "./config.js";
import { HttpError } from "./http/errors.js";

const BCRYPT_ROUNDS = 12;

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function normalizePhone(value: string): string {
  return value.replace(/[^\d+]/g, "");
}

export function createOneTimeCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

export function hashOpaqueToken(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function safeEqualHex(left: string, right: string): boolean {
  if (!/^[a-f0-9]{64}$/i.test(left) || !/^[a-f0-9]{64}$/i.test(right)) {
    return false;
  }
  return timingSafeEqual(Buffer.from(left, "hex"), Buffer.from(right, "hex"));
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

export async function verifyPassword(
  password: string,
  passwordHash: string,
): Promise<boolean> {
  return bcrypt.compare(password, passwordHash);
}

export function createRefreshToken(): string {
  return randomBytes(48).toString("base64url");
}

export function createAccessToken(userId: string, sessionId: string): string {
  return jwt.sign({ sid: sessionId }, config.accessTokenSecret, {
    algorithm: "HS256",
    audience: "orakzai-mobile",
    expiresIn: config.accessTokenTtlSeconds,
    issuer: "orakzai-api",
    subject: userId,
  });
}

export function verifyAccessToken(token: string): {
  userId: string;
  sessionId: string;
} {
  try {
    const payload = jwt.verify(token, config.accessTokenSecret, {
      algorithms: ["HS256"],
      audience: "orakzai-mobile",
      issuer: "orakzai-api",
    });
    if (typeof payload === "string" || !payload.sub || typeof payload.sid !== "string") {
      throw new Error("Invalid token claims.");
    }
    return { userId: payload.sub, sessionId: payload.sid };
  } catch {
    throw new HttpError(401, "UNAUTHENTICATED", "Please sign in again.");
  }
}
