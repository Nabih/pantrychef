import type {
  IngredientsResponse,
  MatchResponse,
  Meta,
  RecipeDetail,
} from "./types";

const BASE = (import.meta.env.VITE_API_URL ?? "").replace(/\/$/, "");

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE}${path}`, {
    headers: { Accept: "application/json", ...init?.headers },
    ...init,
  });

  if (!response.ok) {
    let message = `Request failed (${response.status})`;
    try {
      const body = (await response.json()) as { message?: string };
      if (body.message) message = body.message;
    } catch {
      // keep the status-based message
    }
    throw new Error(message);
  }

  return (await response.json()) as T;
}

export function fetchIngredients(): Promise<IngredientsResponse> {
  return request<IngredientsResponse>("/v1/ingredients?limit=6000");
}

export function fetchMeta(): Promise<Meta> {
  return request<Meta>("/v1/meta");
}

export function fetchMatch(
  ingredientIds: number[],
  maxMinutes: number | null,
): Promise<MatchResponse> {
  const payload: Record<string, unknown> = {
    ingredients: ingredientIds,
    limit: 60,
  };
  if (maxMinutes !== null) payload.maxMinutes = maxMinutes;

  return request<MatchResponse>("/v1/match", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export function fetchRecipe(id: number): Promise<RecipeDetail> {
  return request<RecipeDetail>(`/v1/recipes/${id}`);
}
