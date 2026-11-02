# PantryChef

Pick the ingredients you already have, get recipes ranked by how close you are
to cooking them.

**Status:** vertical slice — ingredient picker, ranked matches, recipe detail.
Built and compiling against iOS 17+, Swift 6, SwiftUI.

---

## Run it

```bash
xcodegen generate                 # regenerate PantryChef.xcodeproj from project.yml
open PantryChef.xcodeproj
```

Command line:

```bash
xcodebuild -project PantryChef.xcodeproj -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Core logic tests (no simulator required):

```bash
cd Packages/PantryCore && swift test
```

Refresh the bundled recipe snapshot (26 API calls):

```bash
python3 Tools/build_catalog.py
```

## Architecture

```
PantryChef/                  SwiftUI app
├── App/                     App entry, observable model, navigation
├── Design/                  Theme tokens
├── Views/                   Pantry picker, results, recipe detail
└── Resources/catalog.json   790-meal snapshot (1.4 MB), bundled

Packages/PantryCore/         Pure Swift, no UI — testable on macOS
├── Models.swift             Meal, IngredientLine, Catalog
├── IngredientNormalizer.swift  Canonical names, aliases, families, aisles
├── RecipeIndex.swift        Pre-computed requirements + ranking
├── MatchEngine.swift        Scoring for ad-hoc meals
└── Catalog+Ingredients.swift   Merged picker options
```

### How matching works

1. **Normalise** every ingredient name to a canonical key
   (`"finely chopped onions"` → `onion`, `"courgettes"` → `zucchini`).
2. **Collapse** synonyms and variants onto a broad *family*
   (`chicken breast`, `chicken thighs` → `chicken`).
3. **Ignore staples** (`salt`, `pepper`, `water`, `oil`) so nobody is penalised
   for things every kitchen has.
4. **Score** each recipe as `matched / required` and show what is missing.

Measured on this catalog: strict "only what I have" filtering returns nothing
for **36 of 40** random ingredient pairs. That is why ranking is the default
rather than filtering — an empty screen is a churn event.

## Data source and licensing

Recipe data and imagery come from [TheMealDB](https://www.themealdb.com/),
fetched through their official API only.

- Their terms permit copying and modifying API content:
  *"You can scrape, copy and modify any content returned from the API, as long
  as you use the official end points."*
- **Publishing to the App Store requires a paid supporter key.** The test key
  (`1`) is for development and educational use only.
- Attribution is required: *"Recipe data and imagery: TheMealDB"* is shown in
  the recipe detail footer.

**Before TestFlight:** buy the one-off supporter key. It also unlocks
`filter.php?i=a,b,c` (multi-ingredient filtering) and larger result sets.

**If that is not an option:** self-hosted [Mealie](https://mealie.io) exposes a
comparable recipe API. Because all data access goes through
`CatalogLoader` / `RecipeIndex`, swapping the source means replacing those two
types, not the UI.

## Known gaps

- Catalog is a point-in-time snapshot (`catalog.json` says when it was fetched).
- Images load from `themealdb.com` at runtime; no 790-image offline bundle yet.
- Pantry selection is in-memory; not persisted between launches.
- No dietary filters — TheMealDB has no reliable vegetarian/vegan/gluten-free
  flags, so those would need to be inferred from ingredients.
- No app icon yet.
