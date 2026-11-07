import { randomUUID } from "node:crypto";

import request from "supertest";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createApp } from "../app.js";
import { pool } from "../db/pool.js";
import { runMigrations } from "../db/migrate.js";

const app = createApp();
const suffix = randomUUID().replaceAll("-", "").slice(0, 12);
const email = `orakzai-test-${suffix}@example.invalid`;
const phone = `+1${Array.from(suffix, (character) => parseInt(character, 16) % 10)
  .join("")
  .slice(0, 10)}`;
const originalPassword = "OrakzaiTestPass123";
let refreshToken = "";
let accessToken = "";
let verificationCode = "";

beforeAll(async () => {
  await runMigrations();
});

afterAll(async () => {
  await pool.query("DELETE FROM users WHERE email = $1", [email]);
  await pool.end();
});

describe("authentication and profile API", () => {
  it("registers a pending account and verifies the email with a one-time code", async () => {
    const registerResponse = await request(app)
      .post("/api/auth/register")
      .send({
        fullName: "Test Community Member",
        email,
        phone,
        password: originalPassword,
      });

    expect(registerResponse.status).toBe(201);
    expect(registerResponse.body.message).toContain("Verify your email");
    const resendResponse = await request(app)
      .post("/api/auth/resend-verification")
      .send({ email });
    expect(resendResponse.status).toBe(202);
    verificationCode = resendResponse.body.devVerificationCode;
    expect(verificationCode).toMatch(/^\d{6}$/);

    const beforeVerification = await request(app)
      .post("/api/auth/login")
      .send({ identifier: email, password: originalPassword });
    expect(beforeVerification.status).toBe(403);
    expect(beforeVerification.body.error.code).toBe("EMAIL_NOT_VERIFIED");

    const verificationResponse = await request(app)
      .post("/api/auth/verify-email")
      .send({ email, code: verificationCode });
    expect(verificationResponse.status).toBe(200);
  });

  it("supports phone login, protected profile access and profile field allowlisting", async () => {
    const loginResponse = await request(app)
      .post("/api/auth/login")
      .send({ identifier: phone, password: originalPassword });
    expect(loginResponse.status).toBe(200);
    accessToken = loginResponse.body.accessToken;
    refreshToken = loginResponse.body.refreshToken;
    expect(accessToken).toBeTruthy();
    expect(refreshToken).toBeTruthy();

    const profileResponse = await request(app)
      .get("/api/users/me")
      .set("Authorization", `Bearer ${accessToken}`);
    expect(profileResponse.status).toBe(200);
    expect(profileResponse.body.user.profile.fullName).toBe("Test Community Member");
    expect(profileResponse.body.user.profile.memberId).toBeNull();

    const updateResponse = await request(app)
      .patch("/api/users/me")
      .set("Authorization", `Bearer ${accessToken}`)
      .send({
        city: "Peshawar",
        showCityPublicly: false,
      });
    expect(updateResponse.status).toBe(200);
    expect(updateResponse.body.user.profile.city).toBe("Peshawar");
    expect(updateResponse.body.user.profile.privacy.showCityPublicly).toBe(false);

    const forbiddenUpdate = await request(app)
      .patch("/api/users/me")
      .set("Authorization", `Bearer ${accessToken}`)
      .send({ memberId: "ORZ-000001" });
    expect(forbiddenUpdate.status).toBe(400);

    const permissions = await request(app)
      .get("/api/users/me/permissions")
      .set("Authorization", `Bearer ${accessToken}`);
    expect(permissions.status).toBe(200);
    expect(permissions.body.roles).toContain("standard_member");
    expect(permissions.body.roles).not.toContain("super_admin");
    expect(permissions.body.permissions).toContain("profile:update:own");

    const roleEscalation = await request(app)
      .post(`/api/admin/users/${profileResponse.body.user.id}/roles`)
      .set("Authorization", `Bearer ${accessToken}`)
      .send({ roleSlug: "super_admin" });
    expect(roleEscalation.status).toBe(403);
  });

  it("rotates refresh tokens and revokes the session on logout", async () => {
    const refreshed = await request(app)
      .post("/api/auth/refresh")
      .send({ refreshToken });
    expect(refreshed.status).toBe(200);
    expect(refreshed.body.refreshToken).not.toBe(refreshToken);

    const oldRefresh = await request(app)
      .post("/api/auth/refresh")
      .send({ refreshToken });
    expect(oldRefresh.status).toBe(401);

    accessToken = refreshed.body.accessToken;
    refreshToken = refreshed.body.refreshToken;
    const logoutResponse = await request(app)
      .post("/api/auth/logout")
      .set("Authorization", `Bearer ${accessToken}`);
    expect(logoutResponse.status).toBe(204);

    const afterLogout = await request(app)
      .post("/api/auth/refresh")
      .send({ refreshToken });
    expect(afterLogout.status).toBe(401);
  });

  it("resets a password without revealing whether an email exists", async () => {
    const absent = await request(app)
      .post("/api/auth/forgot-password")
      .send({ email: `missing-${suffix}@example.invalid` });
    expect(absent.status).toBe(202);

    const forgot = await request(app)
      .post("/api/auth/forgot-password")
      .send({ email });
    expect(forgot.status).toBe(202);
    expect(forgot.body.message).toBe(absent.body.message);
    const resetCode = forgot.body.devResetCode as string;
    expect(resetCode).toMatch(/^\d{6}$/);

    const reset = await request(app)
      .post("/api/auth/reset-password")
      .send({
        email,
        code: resetCode,
        newPassword: "NewOrakzaiPass456",
      });
    expect(reset.status).toBe(200);

    const oldPasswordLogin = await request(app)
      .post("/api/auth/login")
      .send({ identifier: email, password: originalPassword });
    expect(oldPasswordLogin.status).toBe(401);

    const newPasswordLogin = await request(app)
      .post("/api/auth/login")
      .send({ identifier: email, password: "NewOrakzaiPass456" });
    expect(newPasswordLogin.status).toBe(200);
  });
});
