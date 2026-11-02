import Foundation

/// Pre-computed ingredient requirements for a recipe.
///
/// Normalising every ingredient of every recipe on each keystroke is wasteful
/// (790 recipes x ~10 lines). Build this once, then rank freely.
public struct RecipeIndex: Sendable {
    public struct Entry: Sendable {
        public let meal: Meal
        public let requirements: [Requirement]
    }

    public struct Requirement: Sendable {
        public let key: String
        public let family: String?
        public let display: String
    }

    public let entries: [Entry]
    private let normalizer: IngredientNormalizer

    public init(meals: [Meal], normalizer: IngredientNormalizer = .shared) {
        self.normalizer = normalizer
        self.entries = meals.map { meal in
            var seen: Set<String> = []
            var requirements: [Requirement] = []
            for line in meal.ingredients {
                let ingredient = normalizer.canonical(line.name)
                guard !normalizer.isStaple(ingredient.key) else { continue }
                guard seen.insert(ingredient.key).inserted else { continue }
                requirements.append(
                    Requirement(
                        key: ingredient.key,
                        family: ingredient.family,
                        display: ingredient.display
                    )
                )
            }
            return Entry(meal: meal, requirements: requirements)
        }
    }

    public func rank(
        pantry: some Sequence<String>,
        minimumScore: Double = 0.01,
        limit: Int? = nil
    ) -> [RecipeMatch] {
        let selection = PantrySelection(names: Array(pantry), normalizer: normalizer)
        guard !selection.isEmpty else { return [] }

        var results: [RecipeMatch] = []
        results.reserveCapacity(entries.count)

        for entry in entries {
            guard !entry.requirements.isEmpty else { continue }

            var matched: [String] = []
            var missing: [String] = []
            matched.reserveCapacity(entry.requirements.count)
            missing.reserveCapacity(entry.requirements.count)

            for requirement in entry.requirements {
                if selection.contains(key: requirement.key, family: requirement.family) {
                    matched.append(requirement.display)
                } else {
                    missing.append(requirement.display)
                }
            }

            let score = Double(matched.count) / Double(entry.requirements.count)
            guard score >= minimumScore else { continue }
            results.append(
                RecipeMatch(meal: entry.meal, matched: matched, missing: missing, score: score)
            )
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
}
