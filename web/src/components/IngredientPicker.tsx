import { useEffect, useMemo, useRef, useState } from "react";
import type { Ingredient } from "../types";
import { formatCompact } from "../format";

interface Props {
  ingredients: Ingredient[];
  selected: number[];
  onToggle: (id: number) => void;
  onClear: () => void;
}

const MAX_VISIBLE = 120;

// A familiar starting point beats the raw popularity order, which begins
// with sugar and baking powder.
const QUICK_KEYS = [
  "chicken",
  "egg",
  "garlic",
  "onion",
  "tomato",
  "rice",
  "pasta",
  "cheese",
  "potato",
  "carrot",
  "lemon",
  "milk",
];

export function IngredientPicker({
  ingredients,
  selected,
  onToggle,
  onClear,
}: Props) {
  const [query, setQuery] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (
        event.key === "/" &&
        document.activeElement?.tagName !== "INPUT" &&
        document.activeElement?.tagName !== "TEXTAREA"
      ) {
        event.preventDefault();
        inputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const selectedSet = useMemo(() => new Set(selected), [selected]);

  const matches = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return ingredients.slice(0, MAX_VISIBLE);

    return ingredients
      .filter(
        (item) =>
          item.key.includes(needle) || item.display.toLowerCase().includes(needle),
      )
      .sort((a, b) => {
        const aPrefix = a.key.startsWith(needle) ? 1 : 0;
        const bPrefix = b.key.startsWith(needle) ? 1 : 0;
        return bPrefix - aPrefix || b.recipeCount - a.recipeCount;
      })
      .slice(0, MAX_VISIBLE);
  }, [ingredients, query]);

  const quickPicks = useMemo(() => {
    const byKey = new Map(ingredients.map((item) => [item.key, item]));
    return QUICK_KEYS.map((key) => byKey.get(key)).filter(
      (item): item is Ingredient => item !== undefined,
    );
  }, [ingredients]);
  const selectedItems = useMemo(
    () =>
      selected
        .map((id) => ingredients.find((item) => item.id === id))
        .filter((item): item is Ingredient => item !== undefined),
    [ingredients, selected],
  );

  return (
    <div className="picker">
      <div className="search">
        <svg viewBox="0 0 24 24" aria-hidden="true" className="search-icon">
          <circle cx="11" cy="11" r="6.5" />
          <path d="m16 16 4.5 4.5" />
        </svg>
        <input
          ref={inputRef}
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search 5,600 ingredients…"
          aria-label="Search ingredients"
          autoComplete="off"
        />
        <kbd aria-hidden="true">/</kbd>
      </div>

      {selectedItems.length > 0 && (
        <div className="selected-block">
          <div className="selected-head">
            <span>In your kitchen</span>
            <button type="button" className="link-button" onClick={onClear}>
              Clear all
            </button>
          </div>
          <div className="chips">
            {selectedItems.map((item) => (
              <button
                type="button"
                className="chip"
                key={item.id}
                onClick={() => onToggle(item.id)}
                title={`Remove ${item.display}`}
              >
                {item.display}
                <span aria-hidden="true">×</span>
                <span className="sr-only">Remove</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {selectedItems.length === 0 && !query && (
        <div className="quick-picks">
          <span className="quick-label">Start with</span>
          <div className="chips">
            {quickPicks.map((item) => (
              <button
                type="button"
                className="chip chip-ghost"
                key={item.id}
                onClick={() => onToggle(item.id)}
              >
                + {item.display}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="list-head">
        <span>{query ? "Matches" : "All ingredients"}</span>
        <span className="muted">
          {query
            ? `${matches.length}${matches.length === MAX_VISIBLE ? "+" : ""}`
            : formatCompact(ingredients.length)}
        </span>
      </div>

      <ul className="ingredient-list">
        {matches.map((item) => {
          const active = selectedSet.has(item.id);
          return (
            <li key={item.id}>
              <button
                type="button"
                className={active ? "ingredient active" : "ingredient"}
                aria-pressed={active}
                onClick={() => onToggle(item.id)}
              >
                <span className="check" aria-hidden="true">
                  {active && (
                    <svg viewBox="0 0 16 16">
                      <path d="m3.5 8.5 3 3 6-7" />
                    </svg>
                  )}
                </span>
                <span className="ingredient-name">{item.display}</span>
                <span className="ingredient-count">
                  {formatCompact(item.recipeCount)}
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      {matches.length === 0 && (
        <p className="list-empty">
          No ingredient matches “{query}”. Try a shorter word.
        </p>
      )}
      {query && matches.length === MAX_VISIBLE && (
        <p className="list-empty">Showing the first {MAX_VISIBLE} matches.</p>
      )}
    </div>
  );
}
