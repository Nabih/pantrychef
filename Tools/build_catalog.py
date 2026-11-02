#!/usr/bin/env python3
"""Fetch a TheMealDB snapshot and emit a compact catalog for bundling.

Uses only official API endpoints, as required by TheMealDB's terms.
Data and imagery: TheMealDB (https://www.themealdb.com/)
"""

from __future__ import annotations

import json
import re
import time
import urllib.request
from pathlib import Path

API = "https://www.themealdb.com/api/json/v1/{key}/{path}"
TEST_KEY = "1"
OUT = Path(__file__).resolve().parent.parent / "PantryChef" / "Resources" / "catalog.json"

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"[ \t]+")


def fetch(path: str) -> dict:
    url = API.format(key=TEST_KEY, path=path)
    req = urllib.request.Request(url, headers={"User-Agent": "PantryChef/0.1 (dev)"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def clean_text(text: str) -> str:
    if not text:
        return ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = TAG_RE.sub("\n", text)
    text = text.replace("&amp;", "&").replace("&quot;", '"').replace("&#39;", "'")
    lines = [WS_RE.sub(" ", ln).strip() for ln in text.split("\n")]
    lines = [ln for ln in lines if ln]
    return "\n".join(lines)


def steps_from(instructions: str) -> list[str]:
    """Split prose into manageable cooking steps.

    TheMealDB instructions are free-form: some use numbered lists, some use
    paragraph breaks, some are one long block. Split on numbering first, then
    fall back to sentences grouped in threes.
    """
    text = clean_text(instructions)
    if not text:
        return []
    numbered = re.split(r"(?:^|\n)\s*(?:STEP\s*)?\d+[\.\)\-:]\s*", text, flags=re.IGNORECASE)
    numbered = [n.strip() for n in numbered if n.strip()]
    if len(numbered) > 1:
        return numbered

    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    if len(paragraphs) > 1:
        return paragraphs

    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]
    if len(sentences) <= 3:
        return [" ".join(sentences)] if sentences else []
    return [" ".join(sentences[i : i + 3]) for i in range(0, len(sentences), 3)]


def parse_meal(raw: dict) -> dict | None:
    ingredients = []
    for i in range(1, 21):
        name = (raw.get(f"strIngredient{i}") or "").strip()
        measure = (raw.get(f"strMeasure{i}") or "").strip()
        if not name:
            continue
        name = WS_RE.sub(" ", name)
        measure = WS_RE.sub(" ", measure)
        ingredients.append({"name": name, "measure": measure})

    if not ingredients:
        return None

    tags = [t.strip() for t in (raw.get("strTags") or "").split(",") if t.strip()]
    meal_id = raw["idMeal"]

    return {
        "id": meal_id,
        "name": (raw.get("strMeal") or "").strip(),
        "category": (raw.get("strCategory") or "").strip(),
        "area": (raw.get("strArea") or "").strip(),
        "tags": tags,
        "thumb": raw.get("strMealThumb") or "",
        "youtube": raw.get("strYoutube") or "",
        "source": raw.get("strSource") or "",
        "attribution": raw.get("strCreativeCommonsConfirmed") or "",
        "ingredients": ingredients,
        "steps": steps_from(raw.get("strInstructions") or ""),
        "sourceUrl": f"https://www.themealdb.com/meal/{meal_id}",
    }


def main() -> None:
    meals: dict[str, dict] = {}
    for letter in "abcdefghijklmnopqrstuvwxyz":
        try:
            payload = fetch(f"search.php?f={letter}")
        except Exception as exc:  # noqa: BLE001
            print(f"  ! {letter}: {exc}")
            continue
        for raw in payload.get("meals") or []:
            parsed = parse_meal(raw)
            if parsed:
                meals[parsed["id"]] = parsed
        print(f"  {letter}: {len(payload.get('meals') or []):>3}  (total {len(meals)})")
        time.sleep(0.15)

    names = sorted({i["name"].lower() for m in meals.values() for i in m["ingredients"]})
    catalog = {
        "version": 1,
        "source": "TheMealDB",
        "sourceUrl": "https://www.themealdb.com/",
        "attribution": "Recipe data and imagery: TheMealDB (https://www.themealdb.com/)",
        "fetchedAt": time.strftime("%Y-%m-%d"),
        "meals": sorted(meals.values(), key=lambda m: m["name"]),
        "ingredientNames": names,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    size_mb = OUT.stat().st_size / 1_048_576
    print(f"\n{len(meals)} meals, {len(names)} distinct ingredient names -> {OUT} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
