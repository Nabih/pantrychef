import XCTest
@testable import PantryCore

private func meal(_ name: String, _ ingredients: [String]) -> Meal {
    Meal(
        id: name,
        name: name,
        category: "Test",
        area: "Test",
        tags: [],
        thumb: "",
        youtube: "",
        source: "",
        attribution: "",
        ingredients: ingredients.map { IngredientLine(name: $0, measure: "1") },
        steps: [],
        sourceUrl: ""
    )
}

final class MatchEngineTests: XCTestCase {
    let engine = MatchEngine()

    func testEmptyPantryReturnsNothing() {
        let meals = [meal("Soup", ["onion", "carrot"])]
        XCTAssertTrue(engine.rank(pantry: [], meals: meals).isEmpty)
    }

    func testFullMatchScoresOne() {
        let meals = [meal("Soup", ["onion", "carrot", "stock"])]
        let results = engine.rank(pantry: ["onion", "carrot", "stock"], meals: meals)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].score, 1.0, accuracy: 0.001)
        XCTAssertTrue(results[0].missing.isEmpty)
        XCTAssertTrue(results[0].isCookableNow)
    }

    func testPartialMatchReportsMissing() {
        let meals = [meal("Soup", ["onion", "carrot", "stock"])]
        let results = engine.rank(pantry: ["onion", "carrot"], meals: meals)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].score, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(results[0].missing, ["Stock"])
    }

    func testStaplesAreIgnoredInScoring() {
        let meals = [meal("Soup", ["onion", "carrot", "salt", "water", "olive oil"])]
        let results = engine.rank(pantry: ["onion", "carrot"], meals: meals)
        XCTAssertEqual(results[0].score, 1.0, accuracy: 0.001)
        XCTAssertEqual(results[0].totalRequired, 2)
    }

    func testRanksBetterCoverageFirst() {
        let meals = [
            meal("Weak", ["onion", "beef", "carrot", "stock"]),
            meal("Strong", ["onion", "carrot"]),
            meal("Middle", ["onion", "carrot", "stock"]),
        ]
        let results = engine.rank(pantry: ["onion", "carrot"], meals: meals)
        XCTAssertEqual(results.map(\.meal.name), ["Strong", "Middle", "Weak"])
    }

    func testFamilyMatchingCoversChickenVariants() {
        let meals = [meal("Curry", ["chicken breast"])]
        let results = engine.rank(pantry: ["chicken"], meals: meals)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].score, 1.0, accuracy: 0.001)
        XCTAssertTrue(results[0].isCookableNow)
    }

    func testDuplicateIngredientsCountOnce() {
        // "red onion" is a distinct key, but the onion family still covers it.
        let meals = [meal("Dupe", ["onion", "onions", "red onion"])]
        let results = engine.rank(pantry: ["onion"], meals: meals)
        XCTAssertEqual(results[0].totalRequired, 2)
        XCTAssertEqual(results[0].score, 1.0, accuracy: 0.001)
    }

    func testUnrelatedPantryExcluded() {
        let meals = [meal("Soup", ["onion", "carrot"])]
        XCTAssertTrue(engine.rank(pantry: ["chocolate"], meals: meals).isEmpty)
    }

    func testMinimumScoreFilter() {
        let meals = [meal("Soup", ["onion", "carrot", "stock", "cream"])]
        let results = engine.rank(pantry: ["onion"], meals: meals, minimumScore: 0.5)
        XCTAssertTrue(results.isEmpty)
    }
}

final class CatalogTests: XCTestCase {
    /// Loads the real bundled catalog so data problems surface in CI.
    private func loadRealCatalog() throws -> Catalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PantryCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PantryCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("PantryChef/Resources/catalog.json")
        return try CatalogLoader.load(from: root)
    }

    func testCatalogDecodesAndIsSubstantial() throws {
        let catalog = try loadRealCatalog()
        XCTAssertGreaterThan(catalog.meals.count, 500)
        XCTAssertGreaterThan(catalog.ingredientNames.count, 400)
    }

    func testEveryMealHasIngredientsAndSteps() throws {
        let catalog = try loadRealCatalog()
        for meal in catalog.meals {
            XCTAssertFalse(meal.ingredients.isEmpty, "\(meal.name) has no ingredients")
            XCTAssertFalse(meal.steps.isEmpty, "\(meal.name) has no steps")
        }
    }

    func testIngredientOptionsMergeSynonyms() throws {
        let catalog = try loadRealCatalog()
        let options = catalog.ingredientOptions()
        XCTAssertFalse(options.contains { $0.display == "Onions" }, "plurals should be merged")
        XCTAssertTrue(options.contains { $0.display == "Onion" })
        XCTAssertGreaterThan(options.count, 400)
    }

    func testRealisticPantryProducesResults() throws {
        let catalog = try loadRealCatalog()
        let engine = MatchEngine()
        let pantry = ["chicken", "garlic", "onion", "tomato", "rice"]
        let results = engine.rank(pantry: pantry, meals: catalog.meals)

        XCTAssertFalse(results.isEmpty)
        XCTAssertGreaterThanOrEqual(results.first!.score, 0.6)
        // Ranked order must be non-increasing.
        for (a, b) in zip(results, results.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.score, b.score)
        }
    }
}
