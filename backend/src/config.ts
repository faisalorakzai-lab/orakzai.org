import "dotenv/config";

function required(value: string | undefined, name: string): string {
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

const sessionSecret = process.env.ACCESS_TOKEN_SECRET ?? process.env.SESSION_SECRET;
if (!sessionSecret || Buffer.byteLength(sessionSecret) < 32) {
  throw new Error("ACCESS_TOKEN_SECRET or SESSION_SECRET must be at least 32 bytes.");
}

const devAuthMode =
  process.env.NODE_ENV !== "production" && process.env.AUTH_DEV_MODE === "true";

export const config = {
  nodeEnv: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 3001),
  databaseUrl: required(process.env.DATABASE_URL, "DATABASE_URL"),
  accessTokenSecret: sessionSecret,
  accessTokenTtlSeconds: 10 * 60,
  refreshTokenDays: 30,
  verificationCodeMinutes: 10,
  maxVerificationAttempts: 5,
  authDevMode: devAuthMode,
  smtpUrl: process.env.SMTP_URL,
  smtpFrom: process.env.SMTP_FROM,
  corsOrigins: (process.env.CORS_ORIGINS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
  authRateLimitMax:
    process.env.NODE_ENV === "test" ? 100 : Number(process.env.AUTH_RATE_LIMIT_MAX ?? 10),
};
