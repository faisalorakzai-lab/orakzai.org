import nodemailer from "nodemailer";

import { config } from "./config.js";
import { HttpError } from "./http/errors.js";

const transporter =
  config.smtpUrl && config.smtpFrom
    ? nodemailer.createTransport(config.smtpUrl)
    : null;

export function assertEmailDeliveryAvailable(): void {
  if (!config.authDevMode && !transporter) {
    throw new HttpError(
      503,
      "EMAIL_DELIVERY_NOT_CONFIGURED",
      "Email delivery is not configured. Contact the organization administrator.",
    );
  }
}

export async function sendAuthCode(
  recipient: string,
  code: string,
  purpose: "verify your email" | "reset your password",
): Promise<void> {
  if (config.authDevMode) return;
  if (!transporter || !config.smtpFrom) {
    throw new HttpError(
      503,
      "EMAIL_DELIVERY_NOT_CONFIGURED",
      "Email delivery is not configured. Contact the organization administrator.",
    );
  }

  await transporter.sendMail({
    from: config.smtpFrom,
    to: recipient,
    subject: "Your ORAKZAI.ORG security code",
    text: `Use this code to ${purpose}: ${code}. It expires in ${config.verificationCodeMinutes} minutes. If you did not request this, ignore this message.`,
  });
}
