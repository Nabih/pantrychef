#!/usr/bin/env python3
"""Build static matching artifacts from the raw Food.com CSV.

Outputs go to web/public/data and are served straight from a CDN:

  vocab.json          ingredient catalog for the picker (display, group, counts)
  postings.bin        inverted index: ingredient id -> delta-varint recipe ids
  recipes.json        compact per-recipe metadata, aligned with recipe ids
  details/<shard>.json ingredient lines with quantities, fetched on demand
  stats.json          counts used by the UI

The client never normalises anything: it picks ingredient ids from vocab.json
and intersects postings, so the matching logic is a few set operations.
"""

from __future__ import annotations

import csv
import gzip
import html
import json
import os
import re
import struct
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "foodcom_full.csv"
OUT = ROOT / "web" / "public" / "data"

csv.field_size_limit(50 * 1024 * 1024)

WS = re.compile(r"\s+")

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
    "piece", "wedges", "stems", "trimmed", "washed", "drained", "rinsed",
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
    "pantry": "pantry", "oil": "pantry", "salt": "pantry", "sugar": "pantry",
    "stock": "pantry", "soy sauce": "pantry", "vinegar": "pantry",
    "honey": "pantry", "coconut milk": "pantry", "water": "pantry",
    "produce": "produce", "onion": "produce", "garlic": "produce",
    "ginger": "produce", "tomato": "produce", "potato": "produce",
    "carrot": "produce", "mushroom": "produce", "spinach": "produce",
    "broccoli": "produce", "cabbage": "produce", "cucumber": "produce",
    "zucchini": "produce", "eggplant": "produce", "citrus": "produce",
}

STAPLES = {"salt", "pepper", "water", "oil"}

# Long-tail control. User-submitted ingredient strings explode into 189k distinct
# keys; only the head of the distribution is useful in a picker.
MIN_INGREDIENT_COUNT = int(os.environ.get("MIN_ING", "20"))
MIN_KNOWN_PER_RECIPE = int(os.environ.get("MIN_KNOWN", "3"))
MAX_RECIPES = int(os.environ.get("MAX_RECIPES", "0"))  # 0 = keep everything
DEDUPE_BY_NAME = True

KEEP = {
    "couscous", "asparagus", "hummus", "molasses", "swiss", "greens", "rice",
    "pasta", "quinoa", "tahini", "salsa", "pesto", "mayonnaise", "yogurt",
    "cress", "oats", "cheese", "pasta",
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
    return ALIASES.get(key, key)


def family_of(key: str) -> str | None:
    for needle, family in FAMILIES:
        if needle in key:
            return family
    return None


def group_of(key: str) -> str:
    family = family_of(key)
    return GROUP_OF_FAMILY.get(family or "", "other")


def parse_seconds(value: str) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def as_list(value: str) -> list[str]:
    try:
        parsed = json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return []
    if isinstance(parsed, list):
        return [str(v).strip() for v in parsed if str(v).strip()]
    return []


def parse_ingredients(value: str) -> list[dict[str, str]]:
    """The CSV stores parser output, not plain strings: [{quantity, unit, name}]."""
    try:
        parsed = json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(parsed, list):
        return []

    out: list[dict[str, str]] = []
    for item in parsed:
        if isinstance(item, str):
            name = item.strip()
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
            "description": str(item.get("description") or "").strip(),
        })
    return out


def format_line(item: dict[str, str]) -> str:
    head = " ".join(p for p in (item["quantity"], item["unit"], item["name"]) if p)
    note = html.unescape(item["description"])
    head = html.unescape(head)
    if note and len(note) <= 45:
        return f"{head} ({note})"
    return head


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def main() -> None:
    if not RAW.exists():
        raise SystemExit(f"missing {RAW}")

    recipes: list[dict] = []
    vocab_counts: Counter[str] = Counter()

    with open(RAW, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i % 20000 == 0:
                print(f"  read {i:,} rows -> kept {len(recipes):,}", flush=True)

            name = html.unescape(row.get("name") or "").strip()
            name = re.sub(WS, " ", name)
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

            non_staple = [k for k in keys if k not in STAPLES]
            if len(non_staple) < 2:
                continue

            recipes.append({
                "name": name[:90],
                "minutes": max(0, parse_seconds(row.get("cooking_time")))
                + max(0, parse_seconds(row.get("preparation_time"))),
                "calories": row.get("calories") or "",
                "servings": row.get("servings") or "",
                "category": (row.get("RecipeCategory") or "").strip(),
                "ingredients": [format_line(i) for i in ingredients],
                "keys": keys,
            })

    print(f"parsed {len(recipes):,} candidate recipes")

    # --- Long-tail control -------------------------------------------------
    # Count how many *distinct* recipes use each ingredient.
    distinct_counts: Counter[str] = Counter()
    for recipe in recipes:
        for key in recipe["keys"]:
            distinct_counts[key] += 1

    kept_keys = {k for k, c in distinct_counts.items() if c >= MIN_INGREDIENT_COUNT}

    filtered: list[dict] = []
    for recipe in recipes:
        known = [k for k in recipe["keys"] if k in kept_keys]
        if len(known) < MIN_KNOWN_PER_RECIPE:
            continue
        recipe["keys"] = known
        filtered.append(recipe)

    if DEDUPE_BY_NAME:
        best: dict[str, dict] = {}
        for recipe in filtered:
            name_key = recipe["name"].lower().strip()
            current = best.get(name_key)
            if current is None or len(recipe["keys"]) > len(current["keys"]):
                best[name_key] = recipe
        filtered = list(best.values())

    recipes = filtered

    if MAX_RECIPES and len(recipes) > MAX_RECIPES:
        # Prefer recipes with richer ingredient overlap: they are what an
        # ingredient-matching app can reason about.
        recipes.sort(key=lambda r: (len(r["keys"]), -r["minutes"]), reverse=True)
        recipes = recipes[:MAX_RECIPES]

    used_keys = {k for r in recipes for k in r["keys"]}
    counts = Counter({k: distinct_counts[k] for k in used_keys})
    keys = [k for k, _ in counts.most_common()]
    vocab_counts = counts

    print(f"after tail control: {len(recipes):,} recipes, {len(keys):,} ingredients "
          f"(min count {MIN_INGREDIENT_COUNT})")

    # Ingredient catalog, most common first.
    key_to_id = {k: i for i, k in enumerate(keys)}

    vocab = {
        "keys": keys,
        "display": [k[:1].upper() + k[1:] for k in keys],
        "group": [GROUPS.index(group_of(k)) for k in keys],
        "count": [vocab_counts[k] for k in keys],
        "staples": sorted(STAPLES),
    }

    # Inverted index.
    postings: list[list[int]] = [[] for _ in keys]
    for position, recipe in enumerate(recipes):
        for key in recipe["keys"]:
            postings[key_to_id[key]].append(position)

    body = bytearray()
    offsets: list[int] = [0]
    for posting in postings:
        body += varint(len(posting))
        previous = 0
        for value in posting:
            body += varint(value - previous)
            previous = value
        offsets.append(len(body))

    # Category interning keeps recipes.json small.
    categories = sorted({r["category"] for r in recipes if r["category"]})
    cat_id = {c: i for i, c in enumerate(categories)}

    recipe_meta = [
        [
            r["name"],
            r["minutes"],
            int(float(r["calories"])) if r["calories"].replace(".", "", 1).isdigit() else 0,
            int(float(r["servings"])) if str(r["servings"]).replace(".", "", 1).isdigit() else 0,
            cat_id.get(r["category"], -1),
            len([k for k in r["keys"] if k not in STAPLES]),
        ]
        for r in recipes
    ]

    # Detail shards: 512 recipes each, fetched when a recipe is opened.
    SHARD = 512
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "details").mkdir(exist_ok=True)
    for stale in (OUT / "details").glob("*.json"):
        stale.unlink()
    shards: dict[int, dict[str, list[str]]] = {}
    for index, recipe in enumerate(recipes):
        shards.setdefault(index // SHARD, {})[str(index)] = recipe["ingredients"]

    total_detail_gzip = 0
    for shard, payload in shards.items():
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        total_detail_gzip += len(gzip.compress(data))
        (OUT / "details" / f"{shard}.json").write_bytes(data)

    def dump(name: str, payload) -> tuple[int, int]:
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        (OUT / name).write_bytes(data)
        return len(data), len(gzip.compress(data))

    vocab_raw, vocab_gz = dump("vocab.json", vocab)
    meta_raw, meta_gz = dump("recipes.json", recipe_meta)
    cat_raw, cat_gz = dump("categories.json", categories)

    header = struct.pack("<4sII", b"PST1", len(keys), len(recipes))
    offsets_bytes = struct.pack(f"<{len(offsets)}I", *offsets)
    (OUT / "postings.bin").write_bytes(header + offsets_bytes + bytes(body))

    stats = {
        "recipes": len(recipes),
        "ingredients": len(keys),
        "categoryCount": len(categories),
        "builtFrom": "Food.com recipes dataset (CC0 mirror on Hugging Face)",
    }
    dump("stats.json", stats)

    m = 1024 * 1024
    print("\nartifacts ->", OUT)
    print(f"  vocab.json     {vocab_raw/m:6.2f} MB raw  {vocab_gz/m:6.2f} MB gzip  ({len(keys):,} keys)")
    print(f"  postings.bin   {(len(header)+len(offsets_bytes)+len(body))/m:6.2f} MB raw "
          f"({sum(len(p) for p in postings):,} postings)")
    print(f"  recipes.json   {meta_raw/m:6.2f} MB raw  {meta_gz/m:6.2f} MB gzip")
    print(f"  details/       {total_detail_gzip/m:6.2f} MB gzip across {len(shards)} shards")
    print(f"  categories     {cat_raw/m:6.2f} MB raw")
    print(f"  initial payload (vocab + postings + recipes, gzip): "
          f"{(vocab_gz + meta_gz + len(gzip.compress(bytes(body))))/m:.2f} MB")


if __name__ == "__main__":
    main()
