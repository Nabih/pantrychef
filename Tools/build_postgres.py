#!/usr/bin/env python3
"""Build the Postgres read model from the raw Food.com CSV.

Streams the CSV once, writes COPY-ready files, then loads them with psql.
Idempotent: truncates the tables and reloads.

Usage:
    python3 Tools/build_postgres.py            # build + load
    python3 Tools/build_postgres.py --files    # build files only
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "foodcom_full.csv"
BUILD = ROOT / "build"
DATABASE_URL = os.environ.get("DATABASE_URL", "postgres://localhost/pantry")

csv.field_size_limit(50 * 1024 * 1024)

WS = re.compile(r"\s+")
IMAGE_ID = re.compile(r"/recipes/((?:\d+/)+)")
FOODCOM_BASE = "https://www.food.com"
FOODCOM_SEARCH = "https://www.food.com/search/?q="

MIN_INGREDIENT_COUNT = int(os.environ.get("MIN_ING", "20"))
MIN_KNOWN_PER_RECIPE = int(os.environ.get("MIN_KNOWN", "3"))

MODIFIERS = {
    "fresh", "freshly", "dried", "ground", "finely", "roughly", "coarsely",
    "large", "small", "medium", "whole", "half", "chopped", "diced", "minced",
    "sliced", "grated", "crushed", "peeled", "boneless", "skinless", "free",
    "range", "organic", "extra", "virgin", "plain", "natural", "raw", "cooked",
    "ripe", "unripe", "canned", "tinned", "frozen", "mixed", "sweet", "hot",
    "mild", "smoked", "unsalted", "salted", "softened", "melted", "toasted",
    "roasted", "boiled", "steamed", "leftover", "of", "the", "a", "an",
    "some", "plus", "more", "optional", "for", "garnish", "frying", "serving",
    "decoration", "as", "needed", "taste", "thinly", "cut", "into", "chunks",
    "strips", "cubes", "wedges", "and", "or", "about", "approximately",
    "level", "heaped", "generous", "good", "quality", "finest", "divided",
    "such", "brand", "packed", "firmly", "lightly", "warm", "cold", "room",
    "temperature", "refrigerated", "store", "bought", "prepared", "your",
    "favorite", "favourite", "any", "assorted", "sized", "inch", "pieces",
    "piece", "stems", "trimmed", "washed", "drained", "rinsed",
}

PHRASES = [
    "at room temperature", "to taste", "for frying", "for garnish",
    "for serving", "for decoration", "or more", "as needed", "plus extra",
    "finely chopped", "finely grated", "thinly sliced", "roughly chopped",
    "cut into chunks", "free range", "extra virgin", "store bought",
    "ready made", "low fat", "full fat", "such as", "divided",
]

ALIASES = {
    "courgette": "zucchini", "aubergine": "eggplant", "cilantro": "coriander",
    "green onion": "spring onion", "scallion": "spring onion",
    "yoghurt": "yogurt", "garbanzo": "chickpea", "garbanzo bean": "chickpea",
    "chick pea": "chickpea",
    "shrimp": "prawn", "mince": "minced beef", "ground beef": "minced beef",
    "beef mince": "minced beef", "all purpose flour": "flour",
    "self raising flour": "flour", "plain flour": "flour",
    "caster sugar": "sugar", "granulated sugar": "sugar",
    "brown sugar": "sugar", "icing sugar": "sugar",
    "confectioners sugar": "sugar", "olive oil": "oil",
    "vegetable oil": "oil", "sunflower oil": "oil", "sesame oil": "oil",
    "canola oil": "oil", "black pepper": "pepper", "white pepper": "pepper",
    "peppercorns": "pepper", "sea salt": "salt", "table salt": "salt",
    "kosher salt": "salt", "double cream": "cream", "heavy cream": "cream",
    "whipping cream": "cream", "chicken stock": "stock",
    "vegetable stock": "stock", "beef stock": "stock", "chicken broth": "stock",
    "vegetable broth": "stock",
}

# Keys that differ only by cut, part, or wording. A pantry holds "chicken",
# not "chicken breast", so match at the level people actually shop.
FOLD = {
    "garlic clove": "garlic",
    "vanilla extract": "vanilla",
    "lemon juice": "lemon",
    "lime juice": "lime",
    "parmesan cheese": "parmesan",
    "cheddar cheese": "cheddar",
    "mozzarella cheese": "mozzarella",
    "chicken breast": "chicken",
    "chicken thigh": "chicken",
    "chicken leg": "chicken",
    "chicken wing": "chicken",
    "chicken tender": "chicken",
    "chicken piece": "chicken",
    "beef steak": "beef",
    "beef roast": "beef",
    "pork chop": "pork",
    "pork shoulder": "pork",
    "pork loin": "pork",
    "ground turkey": "turkey",
    "turkey breast": "turkey",
    "salmon fillet": "salmon",
    "egg yolk": "egg",
    "egg white": "egg",
}

FAMILIES: list[tuple[str, str]] = [
    ("black pepper", "pepper"), ("white pepper", "pepper"), ("peppercorn", "pepper"),
    ("bell pepper", "bell pepper"), ("red pepper", "bell pepper"),
    ("green pepper", "bell pepper"), ("yellow pepper", "bell pepper"),
    ("chicken", "chicken"), ("beef", "beef"), ("steak", "beef"),
    ("pork", "pork"), ("bacon", "pork"), ("ham", "pork"), ("sausage", "pork"),
    ("lamb", "lamb"), ("turkey", "turkey"), ("duck", "duck"),
    ("salmon", "salmon"), ("tuna", "tuna"), ("cod", "cod"), ("haddock", "cod"),
    ("prawn", "prawn"), ("shrimp", "prawn"), ("crab", "shellfish"),
    ("mussel", "shellfish"), ("squid", "shellfish"), ("anchovy", "anchovy"),
    ("egg", "egg"), ("milk", "milk"), ("cream", "cream"), ("yogurt", "yogurt"),
    ("butter", "butter"), ("cheese", "cheese"), ("parmesan", "cheese"),
    ("cheddar", "cheese"), ("mozzarella", "cheese"), ("feta", "cheese"),
    ("mascarpone", "cheese"), ("ricotta", "cheese"),
    ("onion", "onion"), ("shallot", "onion"), ("scallion", "onion"),
    ("leek", "onion"), ("garlic", "garlic"), ("ginger", "ginger"),
    ("tomato", "tomato"), ("potato", "potato"), ("carrot", "carrot"),
    ("mushroom", "mushroom"), ("spinach", "spinach"), ("broccoli", "broccoli"),
    ("cabbage", "cabbage"), ("cucumber", "cucumber"), ("zucchini", "zucchini"),
    ("eggplant", "eggplant"), ("lemon", "citrus"), ("lime", "citrus"),
    ("orange", "citrus"), ("rice", "rice"), ("pasta", "pasta"),
    ("spaghetti", "pasta"), ("penne", "pasta"), ("macaroni", "pasta"),
    ("noodle", "noodle"), ("bread", "bread"), ("flour", "flour"),
    ("lentil", "lentil"), ("chickpea", "chickpea"), ("bean", "bean"),
    ("coconut milk", "coconut milk"), ("stock", "stock"), ("broth", "stock"),
    ("soy sauce", "soy sauce"), ("vinegar", "vinegar"), ("honey", "honey"),
    ("cumin", "cumin"), ("paprika", "paprika"), ("turmeric", "turmeric"),
    ("cinnamon", "cinnamon"), ("oregano", "oregano"), ("thyme", "thyme"),
    ("rosemary", "rosemary"), ("basil", "basil"), ("parsley", "parsley"),
    ("coriander", "coriander"), ("mint", "mint"), ("dill", "dill"),
    ("sage", "sage"), ("bay leaf", "bay leaf"), ("nutmeg", "nutmeg"),
    ("chili", "chilli"), ("chilli", "chilli"), ("jalapeno", "chilli"),
    ("cayenne", "chilli"), ("curry", "curry"), ("pepper", "bell pepper"),
    ("oil", "oil"), ("salt", "salt"), ("sugar", "sugar"), ("water", "water"),
]

GROUPS = ["produce", "protein", "dairy", "grains", "pantry", "seasoning", "other"]
GROUP_OF_FAMILY = {
    "chicken": "protein", "beef": "protein", "pork": "protein", "lamb": "protein",
    "turkey": "protein", "duck": "protein", "salmon": "protein", "tuna": "protein",
    "cod": "protein", "prawn": "protein", "shellfish": "protein", "anchovy": "protein",
    "egg": "protein", "milk": "dairy", "cream": "dairy", "yogurt": "dairy",
    "butter": "dairy", "cheese": "dairy", "rice": "grains", "pasta": "grains",
    "noodle": "grains", "bread": "grains", "flour": "grains", "lentil": "grains",
    "chickpea": "grains", "bean": "grains", "cumin": "seasoning",
    "paprika": "seasoning", "turmeric": "seasoning", "cinnamon": "seasoning",
    "oregano": "seasoning", "thyme": "seasoning", "rosemary": "seasoning",
    "basil": "seasoning", "parsley": "seasoning", "coriander": "seasoning",
    "mint": "seasoning", "dill": "seasoning", "sage": "seasoning",
    "bay leaf": "seasoning", "nutmeg": "seasoning", "chilli": "seasoning",
    "curry": "seasoning", "pepper": "seasoning", "bell pepper": "seasoning",
    "oil": "pantry", "salt": "pantry", "sugar": "pantry", "stock": "pantry",
    "soy sauce": "pantry", "vinegar": "pantry", "honey": "pantry",
    "coconut milk": "pantry", "water": "pantry", "onion": "produce",
    "garlic": "produce", "ginger": "produce", "tomato": "produce",
    "potato": "produce", "carrot": "produce", "mushroom": "produce",
    "spinach": "produce", "broccoli": "produce", "cabbage": "produce",
    "cucumber": "produce", "zucchini": "produce", "eggplant": "produce",
    "citrus": "produce",
}

STAPLES = {"salt", "pepper", "water", "oil"}

KEEP = {
    "couscous", "asparagus", "hummus", "molasses", "swiss", "greens", "rice",
    "pasta", "quinoa", "tahini", "salsa", "pesto", "mayonnaise", "yogurt",
    "cress", "oats", "cheese",
}


def singular(word: str) -> str:
    if word in KEEP or len(word) <= 3:
        return word
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith("leaves"):
        return word[:-6] + "leaf"
    if word.endswith("loaves"):
        return word[:-6] + "loaf"
    if word.endswith("oes"):
        return word[:-2]
    if word.endswith(("ches", "shes", "sses", "xes", "zes")):
        return word[:-2]
    if word.endswith("s") and not word.endswith(("ss", "us", "is")):
        return word[:-1]
    return word


def normalize(raw: str) -> str:
    text = raw.lower()
    text = re.sub(r"\(.*?\)", " ", text)
    if "," in text:
        parts = [p.strip() for p in text.split(",")]
        meaningful = [p for p in parts if any(t not in MODIFIERS for t in p.split())]
        text = " ".join(meaningful)
    text = text.replace("&", " and ").replace("-", " ")
    for phrase in PHRASES:
        text = text.replace(phrase, " ")
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    tokens = [t.strip("'\".") for t in text.split()]
    tokens = [t for t in tokens if t]
    if "and" in tokens:
        tokens = tokens[: tokens.index("and")]
    while tokens and tokens[0] in MODIFIERS:
        tokens.pop(0)
    while tokens and tokens[-1] in MODIFIERS:
        tokens.pop()
    if not tokens:
        return ""
    tokens[-1] = singular(tokens[-1])
    key = " ".join(tokens)
    key = ALIASES.get(key, key)
    return FOLD.get(key, key)


def group_of(key: str) -> str:
    family = next((fam for needle, fam in FAMILIES if needle in key), None)
    return GROUP_OF_FAMILY.get(family or "", "other")


def parse_seconds(value) -> int:
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def parse_image_id(raw: str) -> int | None:
    if not raw or raw == "[]":
        return None
    try:
        urls = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    for url in urls if isinstance(urls, list) else []:
        match = IMAGE_ID.search(str(url))
        if match:
            return int(match.group(1).replace("/", ""))
    return None


def parse_ingredients(raw: str) -> list[dict[str, str]]:
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(parsed, list):
        return []

    out = []
    for item in parsed:
        if isinstance(item, str):
            name = html.unescape(item).strip()
            if name:
                out.append({"quantity": "", "unit": "", "name": name, "description": ""})
            continue
        if not isinstance(item, dict):
            continue
        name = html.unescape(str(item.get("name") or "")).strip()
        if not name:
            continue
        out.append({
            "quantity": str(item.get("quantity") or "").strip(),
            "unit": str(item.get("unit") or "").strip(),
            "name": name,
            "description": html.unescape(str(item.get("description") or "")).strip(),
        })
    return out


def format_line(item: dict[str, str]) -> str:
    head = " ".join(p for p in (item["quantity"], item["unit"], item["name"]) if p)
    note = item["description"]
    return f"{head} ({note})" if note and len(note) <= 45 else head


def write_csv(path: Path, header: list[str], rows) -> int:
    count = 0
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(header)
        for row in rows:
            writer.writerow(row)
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--files", action="store_true", help="build COPY files only")
    args = parser.parse_args()

    if not RAW.exists():
        sys.exit(f"missing {RAW}")

    started = time.time()
    BUILD.mkdir(exist_ok=True)

    # ---- Pass 1: parse candidates ----------------------------------------
    candidates = []
    with open(RAW, encoding="utf-8", newline="") as f:
        for i, row in enumerate(csv.DictReader(f)):
            if i and i % 50000 == 0:
                print(f"  parsed {i:,} rows...", flush=True)

            name = re.sub(WS, " ", html.unescape(row.get("name") or "")).strip()
            ingredients = parse_ingredients(row.get("ingredients") or "")
            if not name or not (3 <= len(ingredients) <= 25):
                continue

            keys: list[str] = []
            seen: set[str] = set()
            for item in ingredients:
                key = normalize(item["name"])
                if not key or key in seen:
                    continue
                seen.add(key)
                keys.append(key)

            if len([k for k in keys if k not in STAPLES]) < 2:
                continue

            candidates.append({
                "name": name[:120],
                "minutes": parse_seconds(row.get("cooking_time"))
                + parse_seconds(row.get("preparation_time")),
                "calories": row.get("calories") or "",
                "servings": row.get("servings") or "",
                "category": (row.get("RecipeCategory") or "").strip(),
                "ingredients": ingredients,
                "keys": keys,
                "foodcom_id": parse_image_id(row.get("images") or ""),
            })

    print(f"candidates: {len(candidates):,}")

    # ---- Tail control -----------------------------------------------------
    counts: Counter[str] = Counter()
    for recipe in candidates:
        for key in recipe["keys"]:
            counts[key] += 1

    kept = {k for k, c in counts.items() if c >= MIN_INGREDIENT_COUNT}

    filtered = []
    for recipe in candidates:
        known = [k for k in recipe["keys"] if k in kept]
        if len(known) < MIN_KNOWN_PER_RECIPE:
            continue
        recipe["keys"] = known
        filtered.append(recipe)

    # Deduplicate by name, keeping the richest version.
    best: dict[str, dict] = {}
    for recipe in filtered:
        name_key = recipe["name"].lower()
        current = best.get(name_key)
        if current is None or len(recipe["keys"]) > len(current["keys"]):
            best[name_key] = recipe
    recipes = sorted(best.values(), key=lambda r: (r["name"].lower(), r["foodcom_id"] or 0))

    used = {k for r in recipes for k in r["keys"]}
    ordered_keys = [k for k, _ in counts.most_common() if k in used]
    key_to_id = {k: i for i, k in enumerate(ordered_keys)}

    print(f"after tail control: {len(recipes):,} recipes, {len(ordered_keys):,} ingredients")

    # ---- Artifacts --------------------------------------------------------
    categories = sorted({r["category"] for r in recipes if r["category"]})
    category_id = {c: i for i, c in enumerate(categories)}

    def numeric(value) -> int | None:
        text = str(value or "").replace(",", "").strip()
        try:
            return int(float(text))
        except ValueError:
            return None

    recipes_path = BUILD / "recipes.csv"
    with open(recipes_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        for recipe_id, recipe in enumerate(recipes):
            foodcom_id = recipe["foodcom_id"]
            source = (
                f"{FOODCOM_BASE}/recipe/x-{foodcom_id}"
                if foodcom_id
                else FOODCOM_SEARCH + urllib.parse.quote(recipe["name"])
            )
            writer.writerow([
                recipe_id,
                recipe["name"],
                min(recipe["minutes"], 32767),
                numeric(recipe["calories"]),
                numeric(recipe["servings"]),
                category_id.get(recipe["category"]),
                len([k for k in recipe["keys"] if k not in STAPLES]),
                foodcom_id,
                source,
            ])

    ingredients_path = BUILD / "ingredients.csv"
    with open(ingredients_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        for ingredient_id, key in enumerate(ordered_keys):
            writer.writerow([
                ingredient_id,
                key,
                key[:1].upper() + key[1:],
                GROUPS.index(group_of(key)),
                counts[key],
                key in STAPLES,
            ])

    links_path = BUILD / "recipe_ingredients.csv"
    total_links = 0
    with open(links_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        for recipe_id, recipe in enumerate(recipes):
            position = 0
            emitted: set[str] = set()
            for item in recipe["ingredients"]:
                key = normalize(item["name"])
                if key not in key_to_id or key in emitted:
                    continue
                emitted.add(key)
                writer.writerow([
                    recipe_id,
                    key_to_id[key],
                    format_line(item),
                    position,
                ])
                position += 1
                total_links += 1

    categories_path = BUILD / "categories.csv"
    with open(categories_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        for category_id_value, name in enumerate(categories):
            writer.writerow([category_id_value, name])

    print(f"wrote {len(recipes):,} recipes, {len(ordered_keys):,} ingredients, "
          f"{total_links:,} links in {time.time() - started:.0f}s")

    if args.files:
        return

    # ---- Load -------------------------------------------------------------
    psql = ["psql", DATABASE_URL, "-v", "ON_ERROR_STOP=1", "-q"]
    print("loading into postgres...")
    subprocess.run(
        psql + ["-c",
                "TRUNCATE recipe_ingredients, recipes, ingredients, categories CASCADE"],
        check=True,
    )
    for table, path in [
        ("categories", categories_path),
        ("ingredients", ingredients_path),
        ("recipes", recipes_path),
        ("recipe_ingredients", links_path),
    ]:
        subprocess.run(
            psql + ["-c", f"\\copy {table} FROM '{path}' WITH (FORMAT csv)"],
            check=True,
        )
        print(f"  loaded {table}")

    subprocess.run(psql + ["-c", "ANALYZE"], check=True)
    print(f"done in {time.time() - started:.0f}s")


if __name__ == "__main__":
    main()
