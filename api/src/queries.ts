import type { Queryable } from "./db.js";

export const GROUP_NAMES = [
  "produce",
  "protein",
  "dairy",
  "grains",
  "pantry",
  "seasoning",
  "other",
] as const;

export interface Ingredient {
  id: number;
  key: string;
  display: string;
  group: string;
  recipeCount: number;
  isStaple: boolean;
}

export interface IngredientQuery {
  q: string | null;
  limit: number;
  offset: number;
  includeStaples: boolean;
  groupId: number | null;
}

interface IngredientRow {
  id: number;
  key: string;
  display: string;
  group_id: number;
  recipe_count: number;
  is_staple: boolean;
}

const INGREDIENT_COLUMNS = `
  id, key, display, group_id, recipe_count, is_staple
`;

function toIngredient(row: IngredientRow): Ingredient {
  return {
    id: row.id,
    key: row.key,
    display: row.display,
    group: GROUP_NAMES[row.group_id] ?? "other",
    recipeCount: row.recipe_count,
    isStaple: row.is_staple,
  };
}

export async function listIngredients(
  db: Queryable,
  query: IngredientQuery,
): Promise<{ items: Ingredient[]; total: number }> {
  const filters: string[] = [];
  const filterValues: unknown[] = [];
  const orderValues: unknown[] = [];
  let orderClause = "ORDER BY recipe_count DESC, display ASC";

  if (!query.includeStaples) filters.push("NOT is_staple");
  if (query.groupId !== null) {
    filterValues.push(query.groupId);
    filters.push(`group_id = $${filterValues.length}`);
  }

  if (query.q) {
    filterValues.push(`%${query.q}%`);
    const patternIndex = filterValues.length;
    filters.push(`display ILIKE $${patternIndex}`);

    // Prefix matches rank above substring matches, then trigram similarity.
    orderValues.push(`${query.q}%`);
    const prefixIndex = filterValues.length + orderValues.length;
    orderClause = `ORDER BY (display ILIKE $${prefixIndex}) DESC,
                             recipe_count DESC,
                             similarity(display, $${patternIndex}) DESC,
                             display ASC`;
  }

  const where = filters.length ? `WHERE ${filters.join(" AND ")}` : "";

  const countResult = await db.query<{ total: number }>(
    `SELECT count(*)::int AS total FROM ingredients ${where}`,
    filterValues,
  );

  const listValues = [...filterValues, ...orderValues, query.limit, query.offset];
  const rows = await db.query<IngredientRow>(
    `SELECT ${INGREDIENT_COLUMNS}
       FROM ingredients
       ${where}
       ${orderClause}
       LIMIT $${listValues.length - 1} OFFSET $${listValues.length}`,
    listValues,
  );

  return {
    items: rows.rows.map(toIngredient),
    total: countResult.rows[0]?.total ?? 0,
  };
}

export interface IngredientState {
  id: number;
  display: string;
  isStaple: boolean;
}

export async function ingredientsByIds(
  db: Queryable,
  ids: number[],
): Promise<IngredientState[]> {
  const result = await db.query<IngredientState>(
    `SELECT id, display, is_staple AS "isStaple"
       FROM ingredients
      WHERE id = ANY($1::int[])`,
    [ids],
  );
  return result.rows;
}

export interface Category {
  id: number;
  name: string;
  recipeCount: number;
}

export async function listCategories(db: Queryable): Promise<Category[]> {
  const result = await db.query<{
    id: number;
    name: string;
    recipe_count: number;
  }>(
    `SELECT c.id, c.name, count(r.id)::int AS recipe_count
       FROM categories c
       LEFT JOIN recipes r ON r.category_id = c.id
      GROUP BY c.id, c.name
      ORDER BY recipe_count DESC, c.name ASC`,
  );

  return result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    recipeCount: row.recipe_count,
  }));
}

export interface MatchOptions {
  ingredientIds: number[];
  minMatched: number;
  limit: number;
  maxMinutes: number | null;
  categoryId: number | null;
}

export interface MatchRow {
  id: number;
  name: string;
  minutes: number;
  calories: number | null;
  servings: number | null;
  categoryId: number | null;
  category: string | null;
  nIngredients: number;
  matched: number;
  foodcomId: number | null;
  sourceUrl: string;
}

export interface MatchResult extends MatchRow {
  coverage: number;
  missing: string[];
  missingCount: number;
}

export async function matchRecipes(
  db: Queryable,
  options: MatchOptions,
): Promise<MatchResult[]> {
  const result = await db.query<{
    id: number;
    name: string;
    minutes: number;
    calories: number | null;
    servings: number | null;
    category_id: number | null;
    category: string | null;
    n_ingredients: number;
    matched: number;
    foodcom_id: number | null;
    source_url: string;
  }>(
    `WITH hits AS (
       SELECT ri.recipe_id, count(*)::int AS matched
         FROM recipe_ingredients ri
        WHERE ri.ingredient_id = ANY($1::int[])
        GROUP BY ri.recipe_id
       HAVING count(*) >= $2
     )
     SELECT r.id,
            r.name,
            r.minutes,
            r.calories,
            r.servings,
            r.category_id,
            c.name AS category,
            r.n_ingredients,
            r.foodcom_id,
            r.source_url,
            h.matched
       FROM hits h
       JOIN recipes r ON r.id = h.recipe_id
       LEFT JOIN categories c ON c.id = r.category_id
      WHERE r.n_ingredients >= 3
        AND ($3::smallint IS NULL OR r.minutes <= $3)
        AND ($4::smallint IS NULL OR r.category_id = $4)
      ORDER BY (2 * h.matched - r.n_ingredients) DESC,
               (h.matched::float8 / r.n_ingredients) DESC,
               h.matched DESC,
               NULLIF(r.minutes, 0) ASC NULLS LAST,
               r.id ASC
      LIMIT $5`,
    [
      options.ingredientIds,
      options.minMatched,
      options.maxMinutes,
      options.categoryId,
      options.limit,
    ],
  );

  const recipes: MatchRow[] = result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    minutes: row.minutes,
    calories: row.calories,
    servings: row.servings,
    categoryId: row.category_id,
    category: row.category,
    nIngredients: row.n_ingredients,
    matched: row.matched,
    foodcomId: row.foodcom_id,
    sourceUrl: row.source_url,
  }));

  if (recipes.length === 0) return [];

  const missing = await missingIngredients(
    db,
    recipes.map((recipe) => recipe.id),
    options.ingredientIds,
  );

  return recipes.map((recipe) => {
    const names = missing.get(recipe.id) ?? [];
    return {
      ...recipe,
      coverage: recipe.nIngredients === 0 ? 0 : recipe.matched / recipe.nIngredients,
      missing: names.slice(0, 6),
      missingCount: names.length,
    };
  });
}

async function missingIngredients(
  db: Queryable,
  recipeIds: number[],
  haveIds: number[],
): Promise<Map<number, string[]>> {
  const result = await db.query<{ recipe_id: number; display: string }>(
    `SELECT ri.recipe_id, i.display
       FROM recipe_ingredients ri
       JOIN ingredients i ON i.id = ri.ingredient_id
      WHERE ri.recipe_id = ANY($1::int[])
        AND NOT (ri.ingredient_id = ANY($2::int[]))
        AND NOT i.is_staple
      ORDER BY ri.recipe_id, ri.position`,
    [recipeIds, haveIds],
  );

  const grouped = new Map<number, string[]>();
  for (const row of result.rows) {
    const list = grouped.get(row.recipe_id);
    if (list) list.push(row.display);
    else grouped.set(row.recipe_id, [row.display]);
  }
  return grouped;
}

export interface RecipeIngredient {
  id: number;
  display: string;
  line: string;
  isStaple: boolean;
}

export interface RecipeDetail {
  id: number;
  name: string;
  minutes: number;
  calories: number | null;
  servings: number | null;
  categoryId: number | null;
  category: string | null;
  nIngredients: number;
  foodcomId: number | null;
  sourceUrl: string;
  ingredients: RecipeIngredient[];
}

export async function getRecipe(
  db: Queryable,
  id: number,
): Promise<RecipeDetail | null> {
  const recipeResult = await db.query<{
    id: number;
    name: string;
    minutes: number;
    calories: number | null;
    servings: number | null;
    category_id: number | null;
    category: string | null;
    n_ingredients: number;
    foodcom_id: number | null;
    source_url: string;
  }>(
    `SELECT r.id, r.name, r.minutes, r.calories, r.servings,
            r.category_id, c.name AS category, r.n_ingredients,
            r.foodcom_id, r.source_url
       FROM recipes r
       LEFT JOIN categories c ON c.id = r.category_id
      WHERE r.id = $1`,
    [id],
  );

  const recipe = recipeResult.rows[0];
  if (!recipe) return null;

  const ingredientResult = await db.query<{
    id: number;
    display: string;
    line: string;
    is_staple: boolean;
  }>(
    `SELECT i.id, i.display, ri.line, i.is_staple
       FROM recipe_ingredients ri
       JOIN ingredients i ON i.id = ri.ingredient_id
      WHERE ri.recipe_id = $1
      ORDER BY ri.position`,
    [id],
  );

  return {
    id: recipe.id,
    name: recipe.name,
    minutes: recipe.minutes,
    calories: recipe.calories,
    servings: recipe.servings,
    categoryId: recipe.category_id,
    category: recipe.category,
    nIngredients: recipe.n_ingredients,
    foodcomId: recipe.foodcom_id,
    sourceUrl: recipe.source_url,
    ingredients: ingredientResult.rows.map((row) => ({
      id: row.id,
      display: row.display,
      line: row.line,
      isStaple: row.is_staple,
    })),
  };
}
