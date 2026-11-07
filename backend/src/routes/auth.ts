import { Router } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";

import { config } from "../config.js";
import { requireAuth } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";
import {
  login,
  logout,
  refresh,
  register,
  resendEmailVerification,
  requestPasswordReset,
  resetPassword,
  verifyEmail,
} from "../services/auth-service.js";

const authRouter = Router();
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: config.authRateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: {
      code: "RATE_LIMITED",
      message: "Too many attempts. Please wait and try again.",
    },
  },
});
const resetLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: process.env.NODE_ENV === "test" ? 100 : 5,
  standardHeaders: true,
  legacyHeaders: false,
});

const registerSchema = z
  .object({
    fullName: z.string().trim().min(2).max(100),
    email: z.string().trim().email().max(254),
    phone: z.string().trim().regex(/^\+[1-9]\d{7,14}$/, "Use international format, for example +923001234567."),
    password: z
      .string()
      .min(12)
      .max(128)
      .regex(/[A-Za-z]/, "Password must include a letter.")
      .regex(/\d/, "Password must include a number."),
  })
  .strict();

const loginSchema = z
  .object({
    identifier: z.string().trim().min(3).max(254),
    password: z.string().min(1).max(128),
  })
  .strict();

const codeSchema = z
  .object({
    email: z.string().trim().email().max(254),
    code: z.string().regex(/^\d{6}$/),
  })
  .strict();

const forgotSchema = z.object({ email: z.string().trim().email().max(254) }).strict();
const refreshSchema = z
  .object({ refreshToken: z.string().min(32).max(256) })
  .strict();
const resetSchema = z
  .object({
    email: z.string().trim().email().max(254),
    code: z.string().regex(/^\d{6}$/),
    newPassword: z
      .string()
      .min(12)
      .max(128)
      .regex(/[A-Za-z]/, "Password must include a letter.")
      .regex(/\d/, "Password must include a number."),
  })
  .strict();

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) {
    throw new HttpError(400, "VALIDATION_ERROR", result.error.issues[0]?.message ?? "Invalid request.");
  }
  return result.data;
}

authRouter.post("/register", authLimiter, async (request, response) => {
  const input = parseBody(registerSchema, request.body);
  const result = await register(input);
  response.status(201).json(result);
});

authRouter.post("/login", authLimiter, async (request, response) => {
  const input = parseBody(loginSchema, request.body);
  response.json(await login(input.identifier, input.password));
});

authRouter.post("/verify-email", authLimiter, async (request, response) => {
  const input = parseBody(codeSchema, request.body);
  await verifyEmail(input.email, input.code);
  response.json({ message: "Email verified. You can now sign in." });
});

authRouter.post("/resend-verification", resetLimiter, async (request, response) => {
  const input = parseBody(forgotSchema, request.body);
  response.status(202).json(await resendEmailVerification(input.email));
});

authRouter.post("/forgot-password", resetLimiter, async (request, response) => {
  const input = parseBody(forgotSchema, request.body);
  response.status(202).json(await requestPasswordReset(input.email));
});

authRouter.post("/reset-password", resetLimiter, async (request, response) => {
  const input = parseBody(resetSchema, request.body);
  await resetPassword(input.email, input.code, input.newPassword);
  response.json({ message: "Password reset. Sign in with your new password." });
});

authRouter.post("/refresh", authLimiter, async (request, response) => {
  const input = parseBody(refreshSchema, request.body);
  response.json(await refresh(input.refreshToken));
});

authRouter.post("/logout", requireAuth, async (request, response) => {
  const principal = request.auth;
  if (!principal) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  await logout(principal.sessionId, principal.userId);
  response.status(204).end();
});

export default authRouter;
