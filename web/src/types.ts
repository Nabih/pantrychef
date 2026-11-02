export interface Ingredient {
  id: number;
  key: string;
  display: string;
  group: string;
  recipeCount: number;
  isStaple: boolean;
}

export interface IngredientsResponse {
  items: Ingredient[];
  total: number;
  limit: number;
  offset: number;
}

export interface MatchResult {
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
  coverage: number;
  missing: string[];
  missingCount: number;
}

export interface MatchResponse {
  selected: number;
  minMatched: number;
  ignored: { staples: number[]; unknown: number[] };
  results: MatchResult[];
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

export interface Meta {
  groups: string[];
  counts: { recipes: number; ingredients: number; with_source: number };
}
