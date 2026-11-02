import type { MatchResult } from "../types";
import { formatPercent, formatTime } from "../format";

interface Props {
  recipe: MatchResult;
  onOpen: (id: number) => void;
}

export function RecipeCard({ recipe, onOpen }: Props) {
  const percent = Math.round(recipe.coverage * 100);

  return (
    <article
      className="recipe-card"
      onClick={() => onOpen(recipe.id)}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onOpen(recipe.id);
        }
      }}
      role="button"
      tabIndex={0}
      aria-label={`Open ${recipe.name}`}
    >
      <div className="card-top">
        <span className="category">{recipe.category ?? "Uncategorised"}</span>
        <span className="time">{formatTime(recipe.minutes)}</span>
      </div>

      <h3>{recipe.name}</h3>

      <div className="coverage">
        <div className="coverage-track" aria-hidden="true">
          <div className="coverage-fill" style={{ width: `${percent}%` }} />
        </div>
        <span className="coverage-label">
          {recipe.matched}/{recipe.nIngredients} · {formatPercent(recipe.coverage)}
        </span>
      </div>

      <p className="coverage-copy">
        You have {recipe.matched} of {recipe.nIngredients} ingredients
      </p>

      {recipe.missingCount > 0 ? (
        <div className="missing">
          <span className="missing-label">Still need</span>
          <div className="missing-chips">
            {recipe.missing.slice(0, 4).map((name) => (
              <span className="missing-chip" key={name}>
                {name}
              </span>
            ))}
            {recipe.missingCount > 4 && (
              <span className="missing-chip more">
                +{recipe.missingCount - 4}
              </span>
            )}
          </div>
        </div>
      ) : (
        <div className="ready-badge">Everything is in your pantry</div>
      )}

      <footer className="card-footer">
        <span className="card-meta">
          {recipe.calories ? `${recipe.calories} cal` : "Calories n/a"}
          {recipe.servings ? ` · serves ${recipe.servings}` : ""}
        </span>
        <a
          className="source-link"
          href={recipe.sourceUrl}
          target="_blank"
          rel="noopener noreferrer"
          onClick={(event) => event.stopPropagation()}
        >
          {recipe.foodcomId ? "Food.com" : "Search Food.com"} ↗
        </a>
      </footer>
    </article>
  );
}
