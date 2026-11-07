import "dotenv/config";

import { config } from "./config.js";
import { pool } from "./db/pool.js";
import { createApp } from "./app.js";

const app = createApp();
const server = app.listen(config.port, "0.0.0.0", () => {
  console.info(`Orakzai API listening on port ${config.port}.`);
});

async function shutdown(): Promise<void> {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
