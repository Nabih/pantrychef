import { useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchRecipe } from "../api";
import { formatPercent, formatTime } from "../format";

interface Props {
  recipeId: number;
  selectedIds: number[];
  onClose: () => void;
}

export function RecipeDetail({ recipeId, selectedIds, onClose }: Props) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const selected = new Set(selectedIds);

  const { data, isPending, isError, error } = useQuery({
    queryKey: ["recipe", recipeId],
    queryFn: () => fetchRecipe(recipeId),
    staleTime: 10 * 60_000,
  });

  useEffect(() => {
    closeRef.current?.focus();
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKeyDown);

    return () => {
      document.body.style.overflow = previous;
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [onClose]);

  const have = data
    ? data.ingredients.filter(
        (item) => !item.isStaple && selected.has(item.id),
      ).length
    : 0;
  const coverage = data && data.nIngredients > 0 ? have / data.nIngredients : 0;

  return (
    <div
      className="overlay"
      role="presentation"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="sheet" role="dialog" aria-modal="true" aria-labelledby="recipe-title">
        <button
          ref={closeRef}
          type="button"
          className="close-button"
          onClick={onClose}
          aria-label="Close recipe"
        >
          ×
        </button>

        {isPending && (
          <div className="sheet-loading">
            <div className="skeleton skeleton-title" />
            <div className="skeleton skeleton-line" />
            <div className="skeleton skeleton-line short" />
            <div className="skeleton skeleton-block" />
          </div>
        )}

        {isError && (
          <div className="sheet-error">
            <h2>Could not load that recipe</h2>
            <p>{error instanceof Error ? error.message : "Try again."}</p>
          </div>
        )}

        {data && (
          <>
            <header className="sheet-head">
              <span className="category">{data.category ?? "Uncategorised"}</span>
              <h2 id="recipe-title">{data.name}</h2>
              <p className="sheet-meta">
                {formatTime(data.minutes)}
                {data.servings ? ` · serves ${data.servings}` : ""}
                {data.calories ? ` · ${data.calories} cal` : ""}
              </p>
            </header>

            <div className="sheet-coverage">
              <div className="coverage">
                <div className="coverage-track" aria-hidden="true">
                  <div
                    className="coverage-fill"
                    style={{ width: `${Math.round(coverage * 100)}%` }}
                  />
                </div>
                <span className="coverage-label">
                  {have}/{data.nIngredients} · {formatPercent(coverage)}
                </span>
              </div>
              <p className="coverage-copy">
                {have === 0
                  ? "None of these are in your pantry yet."
                  : have === data.nIngredients
                    ? "You already have everything you need."
                    : `You have ${have} of ${data.nIngredients}; pick up the rest.`}
              </p>
            </div>

            <h3 className="sheet-subhead">Ingredients</h3>
            <ul className="ingredient-lines">
              {data.ingredients.map((item) => {
                const state = item.isStaple
                  ? "staple"
                  : selected.has(item.id)
                    ? "have"
                    : "need";
                return (
                  <li key={item.id} className={`line ${state}`}>
                    <span className="line-dot" aria-hidden="true" />
                    <span className="line-text">{item.line}</span>
                    <span className="line-tag">
                      {state === "have"
                        ? "have"
                        : state === "staple"
                          ? "staple"
                          : "need"}
                    </span>
                  </li>
                );
              })}
            </ul>

            <footer className="sheet-footer">
              <p>
                Cooking steps and photos live on Food.com; PantryChef stores the
                ingredient facts only.
              </p>
              <a
                className="primary-button"
                href={data.sourceUrl}
                target="_blank"
                rel="noopener noreferrer"
              >
                {data.foodcomId ? "Open recipe on Food.com" : "Find it on Food.com"} ↗
              </a>
            </footer>
          </>
        )}
      </div>
    </div>
  );
}
