import nodemailer from "nodemailer";
import { describe, expect, it } from "vitest";
import { z } from "zod";

describe("isolated major dependency upgrade contracts", () => {
  it("Nodemailer 10 renders auth-code MIME without contacting SMTP", async () => {
    const transport = nodemailer.createTransport({
      streamTransport: true,
      buffer: true,
      newline: "unix",
    });
    const result = await transport.sendMail({
      from: "Orakzai <sender@example.invalid>",
      to: "recipient@example.invalid",
      subject: "Your ORAKZAI.ORG security code",
      text: "Use this code to verify your email: 123456.",
    });
    const message = result.message.toString();
    expect(message).toContain("To: recipient@example.invalid");
    expect(message).toContain("123456");
    expect(message).toContain("Subject: Your ORAKZAI.ORG security code");
  });

  it("Zod 4 preserves strict validation, issue messages and numeric coercion", () => {
    const schema = z.object({
      email: z.string().email(),
      limit: z.coerce.number().int().min(1).max(50),
    }).strict();
    expect(schema.parse({ email: "member@example.invalid", limit: "20" }).limit).toBe(20);
    const invalid = schema.safeParse({
      email: "invalid",
      limit: "51",
      unexpected: true,
    });
    expect(invalid.success).toBe(false);
    if (!invalid.success) {
      expect(invalid.error.issues.length).toBeGreaterThanOrEqual(3);
      expect(invalid.error.issues[0]?.message).toBeTruthy();
    }
  });
});
