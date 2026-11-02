import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { buildApp } from "./app.js";

const config = loadConfig();
const pool = createPool({
  databaseUrl: config.databaseUrl,
  max: config.poolMax,
  workMem: config.workMem,
});

const app = buildApp({
  pool,
  corsOrigin: config.corsOrigin,
  logger: true,
});

app.log.info(
  { host: config.host, port: config.port, cors: config.corsOrigin },
  "starting pantry api",
);

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "shutting down");
  try {
    await app.close();
    await pool.end();
    process.exit(0);
  } catch (error) {
    app.log.error(error, "shutdown failed");
    process.exit(1);
  }
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error, "failed to start");
  process.exit(1);
}
