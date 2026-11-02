#!/usr/bin/env python3
"""Sanity-check match quality against the built artifacts."""

import json
import struct
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "web" / "public" / "data"

STAPLES = {"salt", "pepper", "water", "oil"}


def read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7


def load():
    vocab = json.loads((DATA / "vocab.json").read_text())
    recipes = json.loads((DATA / "recipes.json").read_text())
    blob = (DATA / "postings.bin").read_bytes()
    magic, ingredient_count, recipe_count = struct.unpack_from("<4sII", blob, 0)
    assert magic == b"PST1", magic
    offsets = struct.unpack_from(f"<{ingredient_count + 1}I", blob, 12)
    body_start = 12 + (ingredient_count + 1) * 4
    body = blob[body_start:]
    postings = []
    for i in range(ingredient_count):
        pos = offsets[i]
        count, pos = read_varint(body, pos)
        ids = []
        current = 0
        for _ in range(count):
            delta, pos = read_varint(body, pos)
            current += delta
            ids.append(current)
        postings.append(ids)
    return vocab, recipes, postings


def main():
    vocab, recipes, postings = load()
    keys = vocab["keys"]
    index = {k: i for i, k in enumerate(keys)}
    print(f"catalog: {len(recipes):,} recipes, {len(keys):,} ingredients\n")

    pantries = [
        ["chicken", "garlic", "onion", "tomato", "rice"],
        ["egg", "cheese", "butter", "milk", "flour"],
        ["beef", "onion", "carrot", "potato"],
        ["salmon", "lemon", "garlic", "butter"],
        ["pasta", "tomato", "olive oil", "onion", "garlic"],
        ["tofu", "soy sauce", "ginger", "garlic"],
    ]

    for pantry in pantries:
        selected = [index[k] for k in pantry if k in index]
        missing_keys = [k for k in pantry if k not in index]
        counts: dict[int, int] = {}
        for ingredient_id in selected:
            for recipe_id in postings[ingredient_id]:
                counts[recipe_id] = counts.get(recipe_id, 0) + 1

        scored = []
        for recipe_id, matched in counts.items():
            row = recipes[recipe_id]
            total = row[5] or 1
            if matched < 2:
                continue
            scored.append((matched / total, matched, recipe_id))

        scored.sort(key=lambda x: (-x[0], -x[1], recipes[x[2]][1] or 9999))
        print(f"pantry {pantry}" + (f"  (unknown: {missing_keys})" if missing_keys else ""))
        print(f"  {len(scored):,} recipes share at least two ingredients")
        for score, matched, recipe_id in scored[:4]:
            name, minutes, calories, servings, category, total = recipes[recipe_id]
            print(f"    {matched}/{total} = {score*100:3.0f}% · {minutes or '?'} min · {name[:56]}")
        print()


if __name__ == "__main__":
    main()
