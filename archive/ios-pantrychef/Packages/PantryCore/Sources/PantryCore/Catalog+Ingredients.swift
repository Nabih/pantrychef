import Foundation

public enum CatalogError: Error {
    case resourceMissing
}

public enum CatalogLoader {
    public static func load(data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }

    public static func load(from url: URL) throws -> Catalog {
        try load(data: Data(contentsOf: url))
    }

    public static func loadBundled(in bundle: Bundle = .main) throws -> Catalog {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        return try load(from: url)
    }
}

/// A selectable ingredient, collapsed from every raw spelling in the catalog.
public struct IngredientOption: Identifiable, Hashable, Sendable {
    /// Canonical key, e.g. `"chicken breast"`.
    public let id: String
    /// A representative raw name, safe to pass back to the normaliser.
    public let raw: String
    public let display: String
    public let group: IngredientGroup
    /// How many recipes in the catalog use it.
    public let mealCount: Int
    public let isStaple: Bool

    public init(raw: String, display: String, group: IngredientGroup, mealCount: Int, isStaple: Bool) {
        self.raw = raw
        self.display = display
        self.group = group
        self.mealCount = mealCount
        self.isStaple = isStaple
        self.id = raw
    }
}

public extension Catalog {
    /// Builds the picker list, merging synonyms onto one option.
    func ingredientOptions(normalizer: IngredientNormalizer = .shared) -> [IngredientOption] {
        var counts: [String: Int] = [:]
        var representatives: [String: String] = [:]

        for meal in meals {
            var seen: Set<String> = []
            for line in meal.ingredients {
                let key = normalizer.canonical(line.name).key
                guard seen.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                // Prefer the longest spelling: "chicken breast" over "chicken".
                let existing = representatives[key]
                if existing == nil || line.name.count > existing!.count {
                    representatives[key] = line.name
                }
            }
        }

        let options = counts.compactMap { key, count -> IngredientOption? in
            guard let raw = representatives[key], !raw.isEmpty else { return nil }
            let ingredient = normalizer.canonical(raw)
            return IngredientOption(
                raw: raw,
                display: ingredient.display,
                group: normalizer.group(for: raw),
                mealCount: count,
                isStaple: normalizer.isStaple(raw)
            )
        }

        let groupOrder = Dictionary(
            uniqueKeysWithValues: IngredientGroup.allCases.enumerated().map { ($1, $0) }
        )

        return options.sorted { lhs, rhs in
            let lg = groupOrder[lhs.group] ?? 99
            let rg = groupOrder[rhs.group] ?? 99
            if lg != rg { return lg < rg }
            if lhs.mealCount != rhs.mealCount { return lhs.mealCount > rhs.mealCount }
            return lhs.display < rhs.display
        }
    }
}
