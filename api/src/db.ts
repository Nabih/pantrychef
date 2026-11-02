import pg from "pg";

export type Queryable = pg.Pool | pg.PoolClient;

export interface PoolOptions {
  databaseUrl: string;
  max?: number;
  /** Ranking aggregates spill to disk at the 4 MB default. */
  workMem?: string;
}

export function createPool(options: PoolOptions): pg.Pool {
  const pool = new pg.Pool({
    connectionString: options.databaseUrl,
    max: options.max ?? 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    options: `-c work_mem=${options.workMem ?? "64MB"}`,
  });

  pool.on("error", (error) => {
    console.error("idle postgres client error", error);
  });

  return pool;
}
