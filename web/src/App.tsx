import { useCallback, useEffect, useMemo, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { fetchIngredients, fetchMatch, fetchMeta } from "./api";
import { formatCompact } from "./format";
import { IngredientPicker } from "./components/IngredientPicker";
import { RecipeCard } from "./components/RecipeCard";
import { RecipeDetail } from "./components/RecipeDetail";

const STORAGE_KEY = "pantrychef.pantry.v1";

function loadPantry(): number[] {
  const fromUrl = new URLSearchParams(window.location.search).get("pantry");
  if (fromUrl) {
    const ids = fromUrl
      .split(",")
      .map((value) => Number.parseInt(value, 10))
      .filter((value) => Number.isInteger(value) && value >= 0);
    if (ids.length > 0) return [...new Set(ids)];
  }

  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((value): value is number => Number.isInteger(value));
  } catch {
    return [];
  }
}

export default function App() {
  const [selected, setSelected] = useState<number[]>(loadPantry);
  const [maxMinutes, setMaxMinutes] = useState<number | null>(null);
  const [detailId, setDetailId] = useState<number | null>(() => {
    const raw = new URLSearchParams(window.location.search).get("recipe");
    if (!raw) return null;
    const id = Number.parseInt(raw, 10);
    return Number.isInteger(id) && id >= 0 ? id : null;
  });

  const ingredientsQuery = useQuery({
    queryKey: ["ingredients"],
    queryFn: fetchIngredients,
    staleTime: Infinity,
  });

  const metaQuery = useQuery({
    queryKey: ["meta"],
    queryFn: fetchMeta,
    staleTime: Infinity,
  });

  const matchQuery = useQuery({
    queryKey: ["match", selected, maxMinutes],
    queryFn: () => fetchMatch(selected, maxMinutes),
    enabled: selected.length > 0,
    staleTime: 60_000,
    placeholderData: keepPreviousData,
  });

  const catalog = ingredientsQuery.data?.items;

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(selected));

    // Keep the pantry and open recipe shareable and refresh-safe.
    const params = new URLSearchParams(window.location.search);
    if (selected.length > 0) params.set("pantry", selected.join(","));
    else params.delete("pantry");
    if (detailId !== null) params.set("recipe", String(detailId));
    else params.delete("recipe");

    const query = params.toString();
    window.history.replaceState(
      null,
      "",
      query ? `${window.location.pathname}?${query}` : window.location.pathname,
    );
  }, [selected, detailId]);

  // Drop ids that no longer exist after a catalogue refresh.
  useEffect(() => {
    if (!catalog || selected.length === 0) return;
    const known = new Set(catalog.map((item) => item.id));
    const next = selected.filter((id) => known.has(id));
    if (next.length !== selected.length) setSelected(next);
  }, [catalog, selected]);

  const toggle = useCallback((id: number) => {
    setSelected((current) =>
      current.includes(id)
        ? current.filter((value) => value !== id)
        : [...current, id],
    );
  }, []);

  const clear = useCallback(() => setSelected([]), []);
  const closeDetail = useCallback(() => setDetailId(null), []);

  const results = matchQuery.data?.results ?? [];
  const selectedIngredients = useMemo(() => {
    if (!catalog) return [];
    const byId = new Map(catalog.map((item) => [item.id, item]));
    return selected
      .map((id) => byId.get(id))
      .filter((item) => item !== undefined);
  }, [catalog, selected]);

  const starterHint = useMemo(() => {
    if (!catalog) return null;
    const byKey = new Map(catalog.map((item) => [item.key, item.display]));
    const picks = ["chicken", "rice", "garlic"]
      .map((key) => byKey.get(key))
      .filter((name): name is string => name !== undefined)
      .map((name) => name.toLowerCase());
    return picks.length === 3
      ? `${picks[0]}, ${picks[1]} and ${picks[2]}`
      : null;
  }, [catalog]);

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <div className="brand-mark" aria-hidden="true">
            <svg viewBox="0 0 32 32">
              <path d="M8 13h16l-1.5 12.5a2 2 0 0 1-2 1.5h-9a2 2 0 0 1-2-1.5L8 13Z" />
              <path d="M12 13V9.5a4 4 0 0 1 8 0V13" />
            </svg>
          </div>
          <div>
            <h1>PantryChef</h1>
            <p>Cook what you already have.</p>
          </div>
        </div>

        <div className="stats">
          {metaQuery.data ? (
            <>
              <span>
                <strong>{formatCompact(metaQuery.data.counts.recipes)}</strong>{" "}
                recipes
              </span>
              <span className="dot" aria-hidden="true" />
              <span>
                <strong>{formatCompact(metaQuery.data.counts.ingredients)}</strong>{" "}
                ingredients
              </span>
            </>
          ) : (
            <span className="muted">Loading catalogue…</span>
          )}
        </div>
      </header>

      <main className="layout">
        <aside className="pantry-panel">
          <div className="panel-head">
            <h2>Your pantry</h2>
            <span className="count-pill">{selected.length}</span>
          </div>

          {ingredientsQuery.isPending && (
            <div className="picker-loading">
              <div className="skeleton skeleton-line" />
              <div className="skeleton skeleton-line short" />
              <div className="skeleton skeleton-block" />
            </div>
          )}

          {ingredientsQuery.isError && (
            <p className="notice">
              Could not load the ingredient catalogue. Is the API running?
            </p>
          )}

          {catalog && (
            <IngredientPicker
              ingredients={catalog}
              selected={selected}
              onToggle={toggle}
              onClear={clear}
            />
          )}
        </aside>

        <section className="results-panel">
          <div className="results-head">
            <div>
              <h2>
                {selected.length === 0
                  ? "What can you cook?"
                  : `${results.length}${results.length === 60 ? "+" : ""} recipe${results.length === 1 ? "" : "s"}`}
              </h2>
              <p className="muted">
                {selected.length === 0
                  ? "Pick a few ingredients to see how close you are."
                  : `Ranked by coverage of your ${selected.length} ingredient${selected.length === 1 ? "" : "s"}.`}
              </p>
            </div>

            <label className="time-filter">
              <span>Time</span>
              <select
                value={maxMinutes ?? ""}
                onChange={(event) =>
                  setMaxMinutes(
                    event.target.value ? Number(event.target.value) : null,
                  )
                }
                disabled={selected.length === 0}
              >
                <option value="">Any</option>
                <option value="30">≤ 30 min</option>
                <option value="45">≤ 45 min</option>
                <option value="60">≤ 1 hr</option>
                <option value="90">≤ 1.5 hr</option>
              </select>
            </label>
          </div>

          {selected.length === 0 && (
            <div className="empty-state">
              <div className="empty-mark" aria-hidden="true">
                <span />
                <span />
                <span />
              </div>
              <h3>Your kitchen is the menu</h3>
              <p>
                Add chicken, rice, garlic — whatever is actually there. Every
                recipe is scored by how much of it you already own, so the
                closest matches rise to the top.
              </p>
              {selectedIngredients.length === 0 && catalog && starterHint && (
                <p className="empty-hint">Try {starterHint}.</p>
              )}
            </div>
          )}

          {selected.length > 0 && matchQuery.isError && (
            <div className="error-banner">
              <strong>Matching failed.</strong>{" "}
              {matchQuery.error instanceof Error
                ? matchQuery.error.message
                : "Please try again."}
            </div>
          )}

          {selected.length > 0 && matchQuery.isPending && (
            <div className="card-grid">
              {Array.from({ length: 6 }, (_, index) => (
                <div className="recipe-card skeleton-card" key={index}>
                  <div className="skeleton skeleton-line short" />
                  <div className="skeleton skeleton-title" />
                  <div className="skeleton skeleton-line" />
                  <div className="skeleton skeleton-block" />
                </div>
              ))}
            </div>
          )}

          {selected.length > 0 &&
            matchQuery.data &&
            results.length === 0 && (
              <div className="empty-state compact">
                <h3>No close matches yet</h3>
                <p>
                  Nothing uses at least {matchQuery.data.minMatched} of these
                  ingredients. Add one or two more, or raise the time limit.
                </p>
              </div>
            )}

          {selected.length > 0 && results.length > 0 && (
            <>
              <div className="card-grid">
                {results.map((recipe) => (
                  <RecipeCard
                    key={recipe.id}
                    recipe={recipe}
                    onOpen={setDetailId}
                  />
                ))}
              </div>
              <p className="results-foot">
                Top {results.length} of millions of combinations. Method and
                photos open on Food.com.
              </p>
            </>
          )}
        </section>
      </main>

      {detailId !== null && (
        <RecipeDetail
          recipeId={detailId}
          selectedIds={selected}
          onClose={closeDetail}
        />
      )}
    </div>
  );
}
