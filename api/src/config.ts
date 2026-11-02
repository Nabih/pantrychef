export interface Config {
  databaseUrl: string;
  host: string;
  port: number;
  /** `true` allows any origin; otherwise an explicit list. */
  corsOrigin: true | string[];
  logLevel: string;
  poolMax: number;
  workMem: string;
}

function parseCors(value: string | undefined): true | string[] {
  if (!value || value.trim() === "" || value.trim() === "*") return true;
  return value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const port = Number.parseInt(env.PORT ?? "8080", 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`invalid PORT: ${env.PORT}`);
  }

  const poolMax = Number.parseInt(env.DB_POOL_MAX ?? "10", 10);
  if (!Number.isInteger(poolMax) || poolMax < 1 || poolMax > 100) {
    throw new Error(`invalid DB_POOL_MAX: ${env.DB_POOL_MAX}`);
  }

  const workMem = env.DB_WORK_MEM ?? "64MB";
  if (!/^\d+(?:kB|MB|GB)$/.test(workMem)) {
    throw new Error(`invalid DB_WORK_MEM: ${workMem}`);
  }

  return {
    databaseUrl: env.DATABASE_URL ?? "postgres://localhost/pantry",
    host: env.HOST ?? "127.0.0.1",
    port,
    corsOrigin: parseCors(env.CORS_ORIGIN),
    logLevel: env.LOG_LEVEL ?? "info",
    poolMax,
    workMem,
  };
}
