import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { createPool } from "../src/db.js";

const databaseUrl =
  process.env.TEST_DATABASE_URL ?? "postgres://localhost/pantry_test";

let app: FastifyInstance;
let pool: ReturnType<typeof createPool>;

beforeAll(async () => {
  pool = createPool({ databaseUrl, max: 2 });
  app = buildApp({ pool, corsOrigin: true });
  await app.ready();
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

interface IngredientBody {
  items: Array<{
    id: number;
    display: string;
    isStaple: boolean;
    group: string;
  }>;
  total: number;
}

interface MatchBody {
  selected: number;
  minMatched: number;
  ignored: { staples: number[]; unknown: number[] };
  results: Array<{
    id: number;
    matched: number;
    coverage: number;
    missing: string[];
    missingCount: number;
  }>;
}

describe("health", () => {
  it("reports the database as reachable", async () => {
    const response = await app.inject({ method: "GET", url: "/health" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok", database: "ok" });
  });
});

describe("GET /v1/ingredients", () => {
  it("finds ingredients by substring, most used first", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/v1/ingredients?q=chick",
    });
    const body = response.json<IngredientBody>();

    expect(response.statusCode).toBe(200);
    expect(body.items.map((item) => item.id)).toContain(1);
    expect(body.items[0]?.display).toBe("Chicken");
  });

  it("hides staples unless asked", async () => {
    const without = await app.inject({
      method: "GET",
      url: "/v1/ingredients?limit=100",
    });
    expect(without.json<IngredientBody>().items.some((i) => i.id === 6)).toBe(
      false,
    );

    const withStaples = await app.inject({
      method: "GET",
      url: "/v1/ingredients?limit=100&includeStaples=true",
    });
    expect(
      withStaples.json<IngredientBody>().items.some((i) => i.id === 6),
    ).toBe(true);
  });

  it("rejects unknown groups", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/v1/ingredients?group=meat",
    });
    expect(response.statusCode).toBe(400);
  });
});

describe("POST /v1/match", () => {
  it("ranks by how much of the recipe is covered", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [1, 5, 3] },
    });
    const body = response.json<MatchBody>();

    expect(response.statusCode).toBe(200);
    expect(body.minMatched).toBe(3);
    expect(body.results.map((result) => result.id)).toEqual([10]);
    expect(body.results[0]).toMatchObject({
      matched: 3,
      coverage: 1,
      missing: [],
      missingCount: 0,
    });
  });

  it("returns the missing ingredients of partial matches", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [1, 5, 3], minMatched: 2 },
    });
    const body = response.json<MatchBody>();

    expect(body.results.map((result) => result.id)).toEqual([10, 12]);
    expect(body.results[1]).toMatchObject({
      id: 12,
      matched: 2,
      missing: ["Tomato"],
      missingCount: 1,
    });
  });

  it("drops recipes with fewer than three non-staple ingredients", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [6], minMatched: 1 },
    });
    // Salt is a staple, so nothing usable remains at all.
    expect(response.statusCode).toBe(422);

    const withRealIngredient = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [5], minMatched: 1 },
    });
    const ids = withRealIngredient
      .json<MatchBody>()
      .results.map((result) => result.id);
    expect(ids).not.toContain(14);
  });

  it("reports staples and unknown ids instead of failing", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [1, 6, 999] },
    });
    const body = response.json<MatchBody>();

    expect(response.statusCode).toBe(200);
    expect(body.selected).toBe(1);
    expect(body.ignored.staples).toEqual([6]);
    expect(body.ignored.unknown).toEqual([999]);
  });

  it("rejects an empty selection", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [] },
    });
    expect(response.statusCode).toBe(400);
  });

  it("filters by cooking time", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/v1/match",
      payload: { ingredients: [1, 5, 3], minMatched: 2, maxMinutes: 25 },
    });
    const body = response.json<MatchBody>();
    expect(body.results.map((result) => result.id)).toEqual([12]);
  });
});

describe("GET /v1/recipes/:id", () => {
  it("returns ordered ingredient lines", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/v1/recipes/10",
    });
    const body = response.json<{
      name: string;
      ingredients: Array<{ display: string; line: string; isStaple: boolean }>;
    }>();

    expect(response.statusCode).toBe(200);
    expect(body.name).toBe("Chicken With Rice");
    expect(body.ingredients.map((item) => item.display)).toEqual([
      "Chicken",
      "Rice",
      "Onion",
      "Salt",
    ]);
    expect(body.ingredients[3]?.isStaple).toBe(true);
  });

  it("404s for a missing recipe", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/v1/recipes/999",
    });
    expect(response.statusCode).toBe(404);
    expect(response.json()).toMatchObject({ error: "not_found" });
  });
});

describe("GET /v1/categories", () => {
  it("counts recipes per category", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/v1/categories",
    });
    const body = response.json<{
      items: Array<{ name: string; recipeCount: number }>;
    }>();

    expect(body.items[0]).toEqual({ id: 0, name: "Dinner", recipeCount: 4 });
  });
});
