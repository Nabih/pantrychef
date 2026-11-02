import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import {
  GROUP_NAMES,
  getRecipe,
  ingredientsByIds,
  listCategories,
  listIngredients,
  matchRecipes,
} from "./queries.js";

export class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

interface IngredientQueryString {
  q?: string;
  limit: number;
  offset: number;
  includeStaples: boolean;
  group?: (typeof GROUP_NAMES)[number];
}

interface MatchBody {
  ingredients: number[];
  limit: number;
  maxMinutes?: number;
  categoryId?: number;
  minMatched?: number;
}

interface IdParams {
  id: number;
}

export function registerRoutes(app: FastifyInstance, pool: Pool): void {
  app.get("/health", async (_request, reply) => {
    try {
      await pool.query("SELECT 1");
      return { status: "ok", database: "ok" };
    } catch (error) {
      app.log.error(error, "health check failed");
      return reply.code(503).send({ status: "degraded", database: "down" });
    }
  });

  app.get(
    "/v1/ingredients",
    {
      schema: {
        querystring: {
          type: "object",
          additionalProperties: false,
          properties: {
            q: { type: "string", maxLength: 80 },
            limit: { type: "integer", minimum: 1, maximum: 6000, default: 200 },
            offset: { type: "integer", minimum: 0, maximum: 100_000, default: 0 },
            includeStaples: { type: "boolean", default: false },
            group: { type: "string", enum: [...GROUP_NAMES] },
          },
        },
      },
    },
    async (request, reply) => {
      const query = request.query as IngredientQueryString;
      const groupIndex = query.group ? GROUP_NAMES.indexOf(query.group) : -1;

      const { items, total } = await listIngredients(pool, {
        q: query.q?.trim() || null,
        limit: query.limit,
        offset: query.offset,
        includeStaples: query.includeStaples,
        groupId: groupIndex >= 0 ? groupIndex : null,
      });

      reply.header("Cache-Control", "public, max-age=300");
      return { items, total, limit: query.limit, offset: query.offset };
    },
  );

  app.get(
    "/v1/categories",
    async (_request, reply) => {
      const categories = await listCategories(pool);
      reply.header("Cache-Control", "public, max-age=3600");
      return { items: categories };
    },
  );

  app.get("/v1/meta", async (_request, reply) => {
    const result = await pool.query<{
      recipes: number;
      ingredients: number;
      with_source: number;
    }>(
      `SELECT (SELECT count(*)::int FROM recipes) AS recipes,
              (SELECT count(*)::int FROM ingredients) AS ingredients,
              (SELECT count(*)::int FROM recipes WHERE foodcom_id IS NOT NULL) AS with_source`,
    );
    reply.header("Cache-Control", "public, max-age=600");
    return {
      groups: GROUP_NAMES,
      counts: result.rows[0] ?? { recipes: 0, ingredients: 0, with_source: 0 },
    };
  });

  app.post<{ Body: MatchBody }>(
    "/v1/match",
    {
      schema: {
        body: {
          type: "object",
          required: ["ingredients"],
          additionalProperties: false,
          properties: {
            ingredients: {
              type: "array",
              items: { type: "integer", minimum: 0 },
              minItems: 1,
              maxItems: 40,
              uniqueItems: true,
            },
            limit: { type: "integer", minimum: 1, maximum: 100, default: 40 },
            maxMinutes: { type: "integer", minimum: 1, maximum: 1440 },
            categoryId: { type: "integer", minimum: 0 },
            minMatched: { type: "integer", minimum: 1, maximum: 40 },
          },
        },
      },
    },
    async (request) => {
      const body = request.body;
      const states = await ingredientsByIds(pool, body.ingredients);
      const known = new Map(states.map((state) => [state.id, state]));

      const unknown = body.ingredients.filter((id) => !known.has(id));
      const staples = body.ingredients.filter((id) => known.get(id)?.isStaple);
      const usable = body.ingredients.filter((id) => {
        const state = known.get(id);
        return state !== undefined && !state.isStaple;
      });

      if (usable.length === 0) {
        throw new ApiError(
          422,
          "no_usable_ingredients",
          "Select at least one ingredient that is not a pantry staple.",
        );
      }

      const minMatched = Math.min(
        body.minMatched ?? Math.min(3, usable.length),
        usable.length,
      );

      const results = await matchRecipes(pool, {
        ingredientIds: usable,
        minMatched,
        limit: body.limit,
        maxMinutes: body.maxMinutes ?? null,
        categoryId: body.categoryId ?? null,
      });

      return {
        selected: usable.length,
        minMatched,
        ignored: { staples, unknown },
        results,
      };
    },
  );

  app.get<{ Params: IdParams }>(
    "/v1/recipes/:id",
    {
      schema: {
        params: {
          type: "object",
          required: ["id"],
          properties: { id: { type: "integer", minimum: 0 } },
        },
      },
    },
    async (request, reply) => {
      const recipe = await getRecipe(pool, request.params.id);
      if (!recipe) {
        throw new ApiError(404, "not_found", "No recipe with that id.");
      }
      reply.header("Cache-Control", "public, max-age=600");
      return recipe;
    },
  );
}
