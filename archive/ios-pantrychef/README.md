# PantryChef — iOS prototype (archived 2026-11-02)

Kept for reference only. The project moved to a VPS-hosted Node API plus a
React web client. Nothing here is maintained.

## What worked

- Full SwiftUI app: ingredient picker, ranked matches, recipe detail
- 22 passing tests against a real 790-meal TheMealDB snapshot
- Matching core in `Packages/PantryCore`:
  - `IngredientNormalizer` — plurals, aliases, preparation words, food families
  - `RecipeIndex` — pre-computed requirements, coverage ranking
  - `MatchEngine` — ad-hoc scoring
- `BUILD SUCCEEDED` against iOS 27.2 (Xcode 27.2, Swift 6.4)

## Why it was shelved

TheMealDB's free catalog is too small for ingredient matching: with
`chicken + garlic + onion` the best coverage was 50%, and 36 of 40 random
ingredient pairs returned zero results. A 400k-recipe Food.com dataset replaced
it, which needs a server — hence the API.

## Rebuilding

```bash
cd archive/ios-pantrychef
xcodegen generate
open PantryChef.xcodeproj
```

Regenerate the bundled catalog (TheMealDB test key, dev use only):

```bash
python3 build_catalog.py
```

## Known issue after archiving

`Packages/PantryCore/Tests/PantryCoreTests/MatchEngineTests.swift` locates the
catalog at `<repo root>/PantryChef/Resources/catalog.json`, which no longer
exists at that path. Change the path to
`archive/ios-pantrychef/PantryChef/Resources/catalog.json`, or copy the
catalog up one level, if you want `swift test` to pass again.

## License note

TheMealDB data is fetched through official endpoints only. Development use is
permitted with test key `1`; publishing to an app store requires a paid
supporter key. Attribution is shown in the recipe detail footer.
