import "dotenv/config";

import { createServer } from "node:http";

import { config } from "./config.js";
import { pool } from "./db/pool.js";
import { createApp } from "./app.js";
import { attachRealtime } from "./realtime.js";

const app = createApp();
const server = createServer(app);
const realtime = attachRealtime(server);
server.listen(config.port, "0.0.0.0", () => {
  console.info(`Orakzai API listening on port ${config.port}.`);
});

async function shutdown(): Promise<void> {
  realtime.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
