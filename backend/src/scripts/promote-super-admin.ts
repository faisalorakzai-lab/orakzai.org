import "dotenv/config";

import { pool } from "../db/pool.js";
import { normalizeEmail } from "../security.js";

async function run(): Promise<void> {
  if (process.env.NODE_ENV === "production") {
    throw new Error("Use an approved production admin procedure; this script is development-only.");
  }
  const email = process.env.BOOTSTRAP_SUPER_ADMIN_EMAIL;
  if (!email) throw new Error("Set BOOTSTRAP_SUPER_ADMIN_EMAIL for the verified account.");

  const existing = await pool.query(
    `SELECT 1 FROM user_roles ur
     JOIN roles r ON r.id = ur.role_id
     WHERE r.slug = 'super_admin'
     LIMIT 1`,
  );
  if (existing.rowCount) {
    throw new Error("A Super Admin already exists; refusing to bootstrap another account.");
  }

  const user = await pool.query<{ id: string }>(
    `SELECT id FROM users
     WHERE email = $1
       AND email_verified_at IS NOT NULL
       AND account_status = 'active'`,
    [normalizeEmail(email)],
  );
  const userId = user.rows[0]?.id;
  if (!userId) throw new Error("The target account must exist and have a verified email.");

  await pool.query(
    `INSERT INTO user_roles (user_id, role_id)
     SELECT $1, id FROM roles WHERE slug = 'super_admin'`,
    [userId],
  );
  await pool.query(
    `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id)
     VALUES ($1, 'admin.bootstrap_super_admin', 'user', $1)`,
    [userId],
  );
  console.info("The verified account received the initial Super Admin role.");
}

run()
  .catch(() => {
    console.error("Super Admin bootstrap failed. Check the account and configuration.");
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
