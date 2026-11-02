import XCTest
@testable import PantryCore

final class IngredientNormalizerTests: XCTestCase {
    let normalizer = IngredientNormalizer()

    func testPluralsAreSingularised() {
        XCTAssertEqual(normalizer.normalize("tomatoes"), "tomato")
        XCTAssertEqual(normalizer.normalize("Chicken Breasts"), "chicken breast")
        XCTAssertEqual(normalizer.normalize("spring onions"), "spring onion")
        XCTAssertEqual(normalizer.normalize("potatoes"), "potato")
        XCTAssertEqual(normalizer.normalize("peaches"), "peach")
    }

    func testPreparationWordsAreStripped() {
        XCTAssertEqual(normalizer.normalize("freshly ground black pepper"), "pepper")
        XCTAssertEqual(normalizer.normalize("finely chopped onion"), "onion")
        XCTAssertEqual(normalizer.normalize("large free-range eggs"), "egg")
        XCTAssertEqual(normalizer.normalize("boneless, skinless chicken thighs"), "chicken thigh")
    }

    func testCommasAndParenthesesAreDropped() {
        XCTAssertEqual(normalizer.normalize("salt, to taste"), "salt")
        XCTAssertEqual(normalizer.normalize("chicken (boneless)"), "chicken")
        XCTAssertEqual(normalizer.normalize("parsley, chopped"), "parsley")
    }

    func testRegionalAliasesCollapse() {
        XCTAssertEqual(normalizer.normalize("courgettes"), "zucchini")
        XCTAssertEqual(normalizer.normalize("aubergine"), "eggplant")
        XCTAssertEqual(normalizer.normalize("cilantro"), "coriander")
        XCTAssertEqual(normalizer.normalize("yoghurt"), "yogurt")
        XCTAssertEqual(normalizer.normalize("shrimp"), "prawn")
    }

    func testFlourAndSugarVariantsCollapse() {
        XCTAssertEqual(normalizer.normalize("plain flour"), "flour")
        XCTAssertEqual(normalizer.normalize("caster sugar"), "sugar")
        XCTAssertEqual(normalizer.normalize("olive oil"), "oil")
        XCTAssertEqual(normalizer.normalize("sea salt"), "salt")
    }

    func testFamiliesAllowFlexibleMatching() {
        XCTAssertEqual(normalizer.canonical("chicken breasts").family, "chicken")
        XCTAssertEqual(normalizer.canonical("chicken thighs").family, "chicken")
        XCTAssertTrue(normalizer.matches("chicken", "chicken breast"))
        XCTAssertTrue(normalizer.matches("onion", "red onions"))
        XCTAssertFalse(normalizer.matches("chicken", "beef"))
    }

    func testStaples() {
        XCTAssertTrue(normalizer.isStaple("salt, to taste"))
        XCTAssertTrue(normalizer.isStaple("olive oil"))
        XCTAssertFalse(normalizer.isStaple("chicken breast"))
    }

    func testGrouping() {
        XCTAssertEqual(normalizer.group(for: "chicken breast"), .protein)
        XCTAssertEqual(normalizer.group(for: "double cream"), .dairy)
        XCTAssertEqual(normalizer.group(for: "basmati rice"), .grains)
        XCTAssertEqual(normalizer.group(for: "smoked paprika"), .seasoning)
        XCTAssertEqual(normalizer.group(for: "red onion"), .produce)
    }

    func testEmptyInputDoesNotCrash() {
        XCTAssertFalse(normalizer.normalize("").isEmpty)
        XCTAssertFalse(normalizer.normalize("   ").isEmpty)
    }
}
