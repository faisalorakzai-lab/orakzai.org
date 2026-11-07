import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { pool } from "./pool.js";

const migrationName = "0001_auth_foundation";
const migrationPath = fileURLToPath(
  new URL("../../migrations/0001_auth_foundation.sql", import.meta.url),
);

export async function runMigrations(): Promise<void> {
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "This migration runner is development-only. Use the configured production schema process.",
    );
  }

  const sql = await readFile(migrationPath, "utf8");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`
      CREATE TABLE IF NOT EXISTS app_schema_migrations (
        name text PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    const existing = await client.query(
      "SELECT 1 FROM app_schema_migrations WHERE name = $1",
      [migrationName],
    );
    if (existing.rowCount === 0) {
      await client.query(sql);
      await client.query(
        "INSERT INTO app_schema_migrations (name) VALUES ($1)",
        [migrationName],
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  runMigrations()
    .then(async () => {
      console.info("Development database migrations are up to date.");
      await pool.end();
    })
    .catch(async () => {
      console.error("Development database migration failed.");
      await pool.end();
      process.exitCode = 1;
    });
}
