import Foundation

/// One ingredient line as authored by the recipe source.
public struct IngredientLine: Codable, Hashable, Sendable {
    public let name: String
    public let measure: String

    public init(name: String, measure: String) {
        self.name = name
        self.measure = measure
    }
}

/// A complete recipe.
public struct Meal: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let area: String
    public let tags: [String]
    public let thumb: String
    public let youtube: String
    public let source: String
    public let attribution: String
    public let ingredients: [IngredientLine]
    public let steps: [String]
    public let sourceUrl: String

    public init(
        id: String,
        name: String,
        category: String,
        area: String,
        tags: [String],
        thumb: String,
        youtube: String,
        source: String,
        attribution: String,
        ingredients: [IngredientLine],
        steps: [String],
        sourceUrl: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.area = area
        self.tags = tags
        self.thumb = thumb
        self.youtube = youtube
        self.source = source
        self.attribution = attribution
        self.ingredients = ingredients
        self.steps = steps
        self.sourceUrl = sourceUrl
    }
}

/// The bundled snapshot of the recipe source.
public struct Catalog: Codable, Sendable {
    public let version: Int
    public let source: String
    public let sourceUrl: String
    public let attribution: String
    public let fetchedAt: String
    public let meals: [Meal]
    public let ingredientNames: [String]

    public init(
        version: Int,
        source: String,
        sourceUrl: String,
        attribution: String,
        fetchedAt: String,
        meals: [Meal],
        ingredientNames: [String]
    ) {
        self.version = version
        self.source = source
        self.sourceUrl = sourceUrl
        self.attribution = attribution
        self.fetchedAt = fetchedAt
        self.meals = meals
        self.ingredientNames = ingredientNames
    }
}
