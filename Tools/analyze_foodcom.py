#!/usr/bin/env python3
"""Profile the Food.com CSV to size the data artifacts before choosing hosting."""

from __future__ import annotations

import csv
import gzip
import json
import re
import statistics
from collections import Counter
from pathlib import Path

RAW = Path(__file__).resolve().parent.parent / "data" / "raw" / "recipes.csv"

LIST_RE = re.compile(r'^c\((.*)\)$', re.DOTALL)
QUOTED_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def parse_list(value: str) -> list[str]:
    if not value or value == "NA":
        return []
    match = LIST_RE.match(value.strip())
    if not match:
        return []
    return [m.group(1).replace('\\"', '"') for m in QUOTED_RE.finditer(match.group(1))]


def parse_duration(value: str) -> int | None:
    """ISO-8601 duration -> minutes."""
    if not value or value == "NA":
        return None
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", value.strip())
    if not m:
        return None
    hours, minutes, seconds = (int(g) if g else 0 for g in m.groups())
    return hours * 60 + minutes + (1 if seconds >= 30 else 0)


def norm(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"\(.*?\)", " ", s)
    s = re.sub(r"[,;].*$", " ", s)
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def main() -> None:
    rows = []
    with open(RAW, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            rows.append(row)

    print(f"rows: {len(rows)}")

    ingredient_counts = []
    all_ingredients = []
    empty = 0
    for row in rows:
        parts = parse_list(row["RecipeIngredientParts"])
        if not parts:
            empty += 1
        ingredient_counts.append(len(parts))
        all_ingredients.extend(parts)

    print(f"recipes with no parsed ingredients: {empty}")
    print(f"ingredients/recipe: mean {statistics.mean(ingredient_counts):.1f}, "
          f"median {statistics.median(ingredient_counts)}, max {max(ingredient_counts)}")
    print(f"total ingredient lines: {len(all_ingredients):,}")
    print(f"unique raw ingredient strings: {len(set(all_ingredients)):,}")
    print(f"unique normalised: {len({norm(i) for i in all_ingredients}):,}")

    # Shortlist: keep only recipes with enough signal to be useful.
    usable = [
        r for r in rows
        if 3 <= len(parse_list(r["RecipeIngredientParts"])) <= 20
    ]
    print(f"usable recipes (3-20 ingredients): {len(usable):,}")

    # --- Estimate artifact sizes -------------------------------------------
    ids = [r["RecipeId"] for r in usable]

    # 1. Ingredient vocabulary
    vocab = sorted({norm(i) for r in usable for i in parse_list(r["RecipeIngredientParts"])})
    vocab_json = json.dumps(vocab, separators=(",", ":")).encode()
    print(f"\nv1 ingredient vocabulary: {len(vocab):,} keys, "
          f"{len(vocab_json) / 1024 / 1024:.2f} MB raw, "
          f"{len(gzip.compress(vocab_json)) / 1024 / 1024:.2f} MB gzip")

    # 2. Postings: ingredient -> [recipe ids]
    key_index = {k: i for i, k in enumerate(vocab)}
    postings: list[list[int]] = [[] for _ in vocab]
    for position, row in enumerate(usable):
        for name in set(norm(i) for i in parse_list(row["RecipeIngredientParts"])):
            if name:
                postings[key_index[name]].append(position)

    total_postings = sum(len(p) for p in postings)
    print(f"total postings: {total_postings:,} "
          f"({total_postings / len(usable):.1f} per recipe)")

    postings_json = json.dumps(postings, separators=(",", ":")).encode()
    print(f"postings JSON: {len(postings_json) / 1024 / 1024:.2f} MB raw, "
          f"{len(gzip.compress(postings_json)) / 1024 / 1024:.2f} MB gzip")

    # Varint delta encoding estimate
    varint_bytes = 0
    for p in postings:
        prev = 0
        for v in p:
            delta = v - prev
            prev = v
            while delta >= 0x80:
                delta >>= 7
                varint_bytes += 1
            varint_bytes += 1
    print(f"postings varint (delta): {varint_bytes / 1024 / 1024:.2f} MB binary, "
          f"~{varint_bytes * 0.55 / 1024 / 1024:.2f} MB gzip-est")

    # 3. Recipe metadata (no instructions, no images)
    meta = []
    for row in usable:
        meta.append([
            row["Name"][:80],
            parse_duration(row["TotalTime"]) or 0,
            float(row["AggregatedRating"] or 0) if row["AggregatedRating"] != "NA" else 0,
            int(float(row["ReviewCount"] or 0)) if row["ReviewCount"] != "NA" else 0,
            int(float(row["Calories"] or 0)) if row["Calories"] != "NA" else 0,
            row["RecipeCategory"][:40] if row["RecipeCategory"] != "NA" else "",
        ])
    meta_json = json.dumps(meta, separators=(",", ":")).encode()
    print(f"\nmetadata JSON ({len(meta):,} rows): {len(meta_json) / 1024 / 1024:.2f} MB raw, "
          f"{len(gzip.compress(meta_json)) / 1024 / 1024:.2f} MB gzip")

    # 4. Detail payload (ingredients only; instructions intentionally excluded)
    details = []
    for row in usable:
        parts = parse_list(row["RecipeIngredientParts"])
        quantities = parse_list(row["RecipeIngredientQuantities"])
        details.append({
            "n": row["Name"][:80],
            "i": [f"{q} {p}".strip() if q and q != "NA" else p
                  for q, p in zip(quantities + [""] * len(parts), parts)],
        })
    details_json = json.dumps(details, separators=(",", ":")).encode()
    per_recipe = len(details_json) / len(details)
    print(f"details JSON: {len(details_json) / 1024 / 1024:.2f} MB raw, "
          f"{len(gzip.compress(details_json)) / 1024 / 1024:.2f} MB gzip "
          f"({per_recipe:.0f} B/recipe)")
    print(f"  sharded into 256 chunks: ~{len(gzip.compress(details_json)) / 256 / 1024:.0f} KB each")

    # 5. How much would instructions add? (kept for reference)
    instr = [parse_list(r["RecipeInstructions"]) for r in usable[:2000]]
    instr_bytes = sum(len(" ".join(s)) for s in instr)
    print(f"\ninstructions avg: {instr_bytes / max(1, len(instr)):.0f} chars/recipe "
          f"(would add ~{instr_bytes / max(1, len(instr)) * len(usable) / 1024 / 1024:.0f} MB raw for all)")

    # 6. Cover check: how often does a common pantry match?
    print("\ntop ingredients:", Counter(norm(i) for i in all_ingredients).most_common(12))


if __name__ == "__main__":
    main()
