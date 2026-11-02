import Foundation

/// A recipe scored against what the user actually has.
public struct RecipeMatch: Identifiable, Hashable, Sendable {
    public let meal: Meal
    /// Canonical keys the user can already cover.
    public let matched: [String]
    /// Canonical keys still needed, in recipe order.
    public let missing: [String]
    /// Share of the non-staple ingredients the user has (0...1).
    public let score: Double

    public var id: String { meal.id }
    public var totalRequired: Int { matched.count + missing.count }

    /// True when every non-staple ingredient is covered.
    public var isCookableNow: Bool { missing.isEmpty }

    public init(meal: Meal, matched: [String], missing: [String], score: Double) {
        self.meal = meal
        self.matched = matched
        self.missing = missing
        self.score = score
    }
}

/// Ranks recipes by how much of each recipe the pantry covers.
///
/// Deliberately lenient: a strict "only what I have" filter returns nothing for
/// most ingredient combinations, so partial matches are surfaced with the
/// missing items called out.
public struct MatchEngine: Sendable {
    private let normalizer: IngredientNormalizer

    public init(normalizer: IngredientNormalizer = .shared) {
        self.normalizer = normalizer
    }

    public func rank(
        pantry: some Sequence<String>,
        meals: [Meal],
        minimumScore: Double = 0.01,
        limit: Int? = nil
    ) -> [RecipeMatch] {
        let selection = PantrySelection(names: Array(pantry), normalizer: normalizer)
        guard !selection.isEmpty else { return [] }

        var results: [RecipeMatch] = []
        results.reserveCapacity(meals.count)

        for meal in meals {
            if let match = score(meal: meal, against: selection, minimumScore: minimumScore) {
                results.append(match)
            }
        }

        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.missing.count != rhs.missing.count { return lhs.missing.count < rhs.missing.count }
            return lhs.meal.name.localizedCaseInsensitiveCompare(rhs.meal.name) == .orderedAscending
        }

        if let limit, results.count > limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    public func score(
        meal: Meal,
        against selection: PantrySelection,
        minimumScore: Double = 0.01
    ) -> RecipeMatch? {
        var requiredKeys: [String] = []
        var requiredFamilies: [String?] = []
        var seen: Set<String> = []
        var matched: [String] = []
        var missing: [String] = []

        for line in meal.ingredients {
            let ingredient = normalizer.canonical(line.name)
            if normalizer.isStaple(ingredient.key) { continue }
            guard seen.insert(ingredient.key).inserted else { continue }

            requiredKeys.append(ingredient.key)
            requiredFamilies.append(ingredient.family)

            if selection.contains(key: ingredient.key, family: ingredient.family) {
                matched.append(ingredient.display)
            } else {
                missing.append(ingredient.display)
            }
        }

        // A recipe made entirely of pantry staples is always "cookable".
        guard !requiredKeys.isEmpty else {
            return RecipeMatch(meal: meal, matched: [], missing: [], score: 0)
        }

        let score = Double(matched.count) / Double(requiredKeys.count)
        guard score >= minimumScore else { return nil }

        return RecipeMatch(meal: meal, matched: matched, missing: missing, score: score)
    }
}

/// The user's current ingredient selection, pre-indexed for fast lookup.
public struct PantrySelection: Sendable {
    private let keys: Set<String>
    private let families: Set<String>
    private let normalizer: IngredientNormalizer

    public init(names: [String], normalizer: IngredientNormalizer = .shared) {
        self.normalizer = normalizer
        var keys: Set<String> = []
        var families: Set<String> = []
        for name in names {
            let ingredient = normalizer.canonical(name)
            keys.insert(ingredient.key)
            if let family = ingredient.family { families.insert(family) }
        }
        self.keys = keys
        self.families = families
    }

    public var isEmpty: Bool { keys.isEmpty }

    public func contains(key: String, family: String?) -> Bool {
        if keys.contains(key) { return true }
        if let family, families.contains(family) { return true }
        return false
    }

    public func contains(_ raw: String) -> Bool {
        let ingredient = normalizer.canonical(raw)
        return contains(key: ingredient.key, family: ingredient.family)
    }
}
