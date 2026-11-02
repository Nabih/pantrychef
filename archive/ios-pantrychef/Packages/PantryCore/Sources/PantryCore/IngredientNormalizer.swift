import Foundation

/// A pantry-facing version of a raw ingredient string.
///
/// Recipe sources spell things inconsistently ("chicken breasts", "freshly
/// ground black pepper", "courgettes"). Matching on raw strings fails, so
/// every name is reduced to a canonical key plus an optional broad family.
public struct CanonicalIngredient: Hashable, Sendable {
    /// Canonical singular form, e.g. `"chicken breast"`.
    public let key: String
    /// Broad family used for flexible matching, e.g. `"chicken"`.
    public let family: String?
    /// Display form, e.g. `"Chicken Breast"`.
    public let display: String

    public init(key: String, family: String?, display: String) {
        self.key = key
        self.family = family
        self.display = display
    }
}

/// Aisle-style grouping used by the ingredient picker.
public enum IngredientGroup: String, CaseIterable, Sendable {
    case produce, protein, dairy, grains, pantry, seasoning, other

    public var title: String {
        switch self {
        case .produce: "Fruit & Veg"
        case .protein: "Meat & Fish"
        case .dairy: "Dairy"
        case .grains: "Grains & Pulses"
        case .pantry: "Pantry"
        case .seasoning: "Herbs & Spices"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .produce: "leaf"
        case .protein: "fish"
        case .dairy: "drop"
        case .grains: "circle.grid.2x2"
        case .pantry: "shippingbox"
        case .seasoning: "sparkles"
        case .other: "questionmark"
        }
    }
}

/// Normalises ingredient names and classifies them.
public struct IngredientNormalizer: Sendable {
    public static let shared = IngredientNormalizer()

    public init() {}

    // MARK: - Vocabulary

    /// Words that describe preparation, size or provenance rather than the
    /// ingredient itself. Stripped from either end of a name.
    private static let modifiers: Set<String> = [
        "fresh", "freshly", "dried", "ground", "finely", "roughly", "coarsely",
        "large", "small", "medium", "whole", "half", "chopped", "diced", "minced",
        "sliced", "grated", "crushed", "peeled", "boneless", "skinless", "free",
        "range", "organic", "extra", "virgin", "plain", "natural", "raw", "cooked",
        "ripe", "unripe", "canned", "tinned", "frozen", "mixed", "sweet", "hot",
        "mild", "smoked", "unsalted", "salted", "softened", "melted", "toasted",
        "roasted", "boiled", "steamed", "leftover", "of", "the", "a", "an",
        "some", "plus", "more", "optional", "for", "garnish", "frying", "serving",
        "decoration", "as", "needed", "taste", "thinly", "cut", "into", "chunks",
        "strips", "cubes", "wedges", "and", "or", "about", "approximately",
        "level", "heaped", "generous", "good", "quality", "finest", "shop",
        "bought", "store", "made", "ready", "low", "fat", "full", "reduced",
        "skimmed", "semi", "double", "single", "thick", "thin", "clear",
    ]

    /// Multi-word preparation phrases removed before token stripping.
    private static let phrases: [String] = [
        "at room temperature", "to taste", "for frying", "for garnish",
        "for serving", "for decoration", "or more", "as needed", "plus extra",
        "finely chopped", "finely grated", "thinly sliced", "roughly chopped",
        "cut into chunks", "free range", "extra virgin", "store bought",
        "ready made", "low fat", "full fat",
    ]

    /// Ingredient equivalences. Keys are already-lowercased raw names.
    private static let aliases: [String: String] = [
        "courgette": "zucchini",
        "aubergine": "eggplant",
        "coriander": "coriander",
        "cilantro": "coriander",
        "spring onion": "spring onion",
        "green onion": "spring onion",
        "scallion": "spring onion",
        "yoghurt": "yogurt",
        "garbanzo": "chickpea",
        "garbanzo bean": "chickpea",
        "shrimp": "prawn",
        "prawns": "prawn",
        "mince": "minced beef",
        "minced meat": "minced beef",
        "ground beef": "minced beef",
        "beef mince": "minced beef",
        "all purpose flour": "flour",
        "self raising flour": "flour",
        "plain flour": "flour",
        "caster sugar": "sugar",
        "granulated sugar": "sugar",
        "brown sugar": "sugar",
        "icing sugar": "sugar",
        "confectioners sugar": "sugar",
        "olive oil": "oil",
        "vegetable oil": "oil",
        "sunflower oil": "oil",
        "sesame oil": "oil",
        "rapeseed oil": "oil",
        "black pepper": "pepper",
        "white pepper": "pepper",
        "peppercorns": "pepper",
        "sea salt": "salt",
        "table salt": "salt",
        "rock salt": "salt",
        "double cream": "cream",
        "single cream": "cream",
        "heavy cream": "cream",
        "whipping cream": "cream",
        "chicken stock": "stock",
        "vegetable stock": "stock",
        "beef stock": "stock",
        "chicken broth": "stock",
        "vegetable broth": "stock",
    ]

    /// Broad families. Ordered: the first needle contained in the key wins.
    /// Order matters — `"bell pepper"` must be checked before `"pepper"`.
    private static let familyRules: [(needle: String, family: String)] = [
        ("black pepper", "pepper"), ("white pepper", "pepper"), ("peppercorn", "pepper"),
        ("bell pepper", "bell pepper"), ("red pepper", "bell pepper"),
        ("green pepper", "bell pepper"), ("yellow pepper", "bell pepper"),
        ("chicken", "chicken"), ("beef", "beef"), ("steak", "beef"),
        ("pork", "pork"), ("bacon", "pork"), ("ham", "pork"), ("sausage", "pork"),
        ("lamb", "lamb"), ("turkey", "turkey"), ("duck", "duck"),
        ("salmon", "salmon"), ("tuna", "tuna"), ("cod", "cod"), ("haddock", "cod"),
        ("prawn", "prawn"), ("crab", "shellfish"), ("mussel", "shellfish"),
        ("squid", "shellfish"), ("anchovy", "anchovy"),
        ("egg", "egg"), ("milk", "milk"), ("cream", "cream"), ("yogurt", "yogurt"),
        ("butter", "butter"), ("cheese", "cheese"), ("parmesan", "cheese"),
        ("cheddar", "cheese"), ("mozzarella", "cheese"), ("feta", "cheese"),
        ("mascarpone", "cheese"), ("ricotta", "cheese"),
        ("onion", "onion"), ("shallot", "onion"), ("scallion", "onion"),
        ("leek", "onion"),
        ("garlic", "garlic"), ("ginger", "ginger"),
        ("tomato", "tomato"), ("potato", "potato"), ("carrot", "carrot"),
        ("mushroom", "mushroom"), ("spinach", "spinach"), ("broccoli", "broccoli"),
        ("cabbage", "cabbage"), ("cucumber", "cucumber"), ("zucchini", "zucchini"),
        ("eggplant", "eggplant"), ("aubergine", "eggplant"),
        ("lemon", "citrus"), ("lime", "citrus"), ("orange", "citrus"),
        ("rice", "rice"), ("pasta", "pasta"), ("spaghetti", "pasta"),
        ("penne", "pasta"), ("macaroni", "pasta"), ("noodle", "noodle"),
        ("bread", "bread"), ("flour", "flour"),
        ("lentil", "lentil"), ("chickpea", "chickpea"), ("bean", "bean"),
        ("coconut milk", "coconut milk"), ("coconut cream", "coconut milk"),
        ("stock", "stock"), ("broth", "stock"),
        ("soy sauce", "soy sauce"), ("vinegar", "vinegar"), ("honey", "honey"),
        ("cumin", "cumin"), ("paprika", "paprika"), ("turmeric", "turmeric"),
        ("cinnamon", "cinnamon"), ("oregano", "oregano"), ("thyme", "thyme"),
        ("rosemary", "rosemary"), ("basil", "basil"), ("parsley", "parsley"),
        ("coriander", "coriander"), ("mint", "mint"), ("dill", "dill"),
        ("sage", "sage"), ("bay leaf", "bay leaf"), ("nutmeg", "nutmeg"),
        ("chilli", "chilli"), ("chili", "chilli"), ("jalapeno", "chilli"),
        ("cayenne", "chilli"), ("curry", "curry"),
        ("pepper", "bell pepper"),
        ("oil", "oil"), ("salt", "salt"), ("sugar", "sugar"), ("water", "water"),
    ]

    /// Ingredients most kitchens already have. They are excluded from the
    /// score so users aren't penalised for "water" or "salt".
    public static let staples: Set<String> = [
        "salt", "pepper", "water", "oil",
    ]

    /// Aisle overrides, checked before the family fallback. Keeps the picker
    /// navigable without inflating the family table.
    private static let groupRules: [(needle: String, group: IngredientGroup)] = [
        ("vinegar", .pantry), ("green bean", .produce), ("runner bean", .produce),
        ("chorizo", .protein), ("sausage", .protein), ("pancetta", .protein),
        ("prosciutto", .protein), ("salami", .protein), ("pepperoni", .protein),
        ("scotch bonnet", .produce), ("bonnet", .produce),
        ("worcestershire", .pantry), ("creme fraiche", .dairy),
        ("pastry", .pantry), ("filo", .pantry), ("puff", .pantry),
        ("baguette", .grains), ("ciabatta", .grains), ("sourdough", .grains),
        ("hotsauce", .pantry), ("hot sauce", .pantry), ("sherry", .pantry),
        ("brandy", .pantry), ("rum", .pantry), ("whiskey", .pantry),
        ("vodka", .pantry), ("dulce de leche", .dairy), ("condensed milk", .dairy),
        ("celery", .produce), ("lettuce", .produce), ("avocado", .produce),
        ("corn", .produce), ("pea", .produce), ("pumpkin", .produce),
        ("squash", .produce), ("beetroot", .produce), ("radish", .produce),
        ("asparagus", .produce), ("apple", .produce), ("banana", .produce),
        ("pear", .produce), ("peach", .produce), ("plum", .produce),
        ("mango", .produce), ("pineapple", .produce), ("strawberr", .produce),
        ("blueberr", .produce), ("raspberr", .produce), ("apricot", .produce),
        ("grape", .produce), ("kiwi", .produce), ("fig", .produce),
        ("olive", .pantry), ("caper", .pantry), ("raisin", .pantry),
        ("date", .pantry), ("coconut", .pantry),

        ("allspice", .seasoning), ("cardamom", .seasoning), ("clove", .seasoning),
        ("fennel", .seasoning), ("saffron", .seasoning), ("tarragon", .seasoning),
        ("chive", .seasoning), ("lemongrass", .seasoning), ("anise", .seasoning),
        ("mixed spice", .seasoning), ("garam masala", .seasoning),
        ("seasoning", .seasoning), ("herb", .seasoning), ("spice", .seasoning),
        ("mustard", .seasoning), ("horseradish", .seasoning),

        ("baking powder", .pantry), ("baking soda", .pantry),
        ("bicarbonate", .pantry), ("cornstarch", .pantry), ("cornflour", .pantry),
        ("vanilla", .pantry), ("fish sauce", .pantry), ("oyster sauce", .pantry),
        ("hoisin", .pantry), ("ketchup", .pantry), ("mayonnaise", .pantry),
        ("tomato puree", .pantry), ("tomato paste", .pantry),
        ("passata", .pantry), ("chocolate", .pantry), ("cocoa", .pantry),
        ("coffee", .pantry), ("jam", .pantry), ("peanut butter", .pantry),
        ("almond", .pantry), ("cashew", .pantry), ("walnut", .pantry),
        ("peanut", .pantry), ("pistachio", .pantry), ("hazelnut", .pantry),
        ("sesame", .pantry), ("wine", .pantry), ("beer", .pantry),
        ("stock cube", .pantry), ("gelatine", .pantry), ("yeast", .pantry),
        ("syrup", .pantry), ("marmalade", .pantry), ("noodle", .pantry),

        ("breadcrumb", .grains), ("cornmeal", .grains), ("polenta", .grains),
        ("oat", .grains), ("quinoa", .grains), ("barley", .grains),
        ("couscous", .grains), ("cracker", .grains), ("tortilla", .grains),
        ("pita", .grains), ("naan", .grains),
    ]

    // MARK: - Normalisation

    public func canonical(_ raw: String) -> CanonicalIngredient {
        let key = normalize(raw)
        let family = Self.familyRules.first { key.contains($0.needle) }?.family
        return CanonicalIngredient(key: key, family: family, display: key.capitalized)
    }

    /// Reduces a raw ingredient name to a stable singular key.
    public func normalize(_ raw: String) -> String {
        var text = raw.lowercased()

        // Drop parenthetical asides: "chicken (boneless)".
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }

        // Drop comma-separated asides that are pure preparation notes, but keep
        // meaningful segments: "salt, to taste" -> "salt" yet
        // "boneless, skinless chicken thighs" -> "chicken thighs".
        if text.contains(",") {
            let parts = text.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let meaningful = parts.filter { part in
                part.split(separator: " ").contains { !Self.modifiers.contains(String($0)) }
            }
            text = meaningful.joined(separator: " ")
        }

        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: "-", with: " ")

        for phrase in Self.phrases {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }

        // Keep only letters, digits and spaces.
        text = String(text.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " })

        var tokens = text.split(separator: " ").map(String.init)
        tokens = tokens.map(stripPunctuation).filter { !$0.isEmpty }

        // "salt and pepper" -> "salt": only the lead ingredient matters.
        if let andIndex = tokens.firstIndex(of: "and") {
            tokens = Array(tokens[..<andIndex])
        }

        while let first = tokens.first, Self.modifiers.contains(first) {
            tokens.removeFirst()
        }
        while let last = tokens.last, Self.modifiers.contains(last) {
            tokens.removeLast()
        }

        guard !tokens.isEmpty else {
            // Keeps the key non-empty so unparseable lines stay distinct
            // instead of collapsing onto one empty key.
            let fallback = raw.lowercased().trimmingCharacters(in: .whitespaces)
            return fallback.isEmpty ? "unknown" : fallback
        }

        lockKnownAliases(&tokens)
        tokens[tokens.count - 1] = singular(tokens[tokens.count - 1])

        var key = tokens.joined(separator: " ")
        if let alias = Self.aliases[key] {
            key = alias
        }
        return key
    }

    public func display(_ raw: String) -> String {
        canonical(raw).display
    }

    /// True when two raw names should be considered interchangeable.
    public func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = canonical(lhs)
        let b = canonical(rhs)
        if a.key == b.key { return true }
        if let fa = a.family, let fb = b.family, fa == fb { return true }
        return false
    }

    public func isStaple(_ raw: String) -> Bool {
        let ingredient = canonical(raw)
        return Self.staples.contains(ingredient.key)
    }

    public func group(for raw: String) -> IngredientGroup {
        let ingredient = canonical(raw)
        if let override = Self.groupRules.first(where: { ingredient.key.contains($0.needle) }) {
            return override.group
        }
        switch ingredient.family {
        case "chicken", "beef", "pork", "lamb", "turkey", "duck", "salmon",
             "tuna", "cod", "prawn", "shellfish", "anchovy", "egg":
            return .protein
        case "milk", "cream", "yogurt", "butter", "cheese":
            return .dairy
        case "rice", "pasta", "noodle", "bread", "flour", "lentil", "chickpea", "bean":
            return .grains
        case "cumin", "paprika", "turmeric", "cinnamon", "oregano", "thyme",
             "rosemary", "basil", "parsley", "coriander", "mint", "dill", "sage",
             "bay leaf", "nutmeg", "chilli", "curry", "pepper", "bell pepper":
            return .seasoning
        case "oil", "salt", "sugar", "stock", "soy sauce", "vinegar", "honey",
             "coconut milk", "water":
            return .pantry
        case "onion", "garlic", "ginger", "tomato", "potato", "carrot", "mushroom",
             "spinach", "broccoli", "cabbage", "cucumber", "zucchini", "eggplant",
             "citrus":
            return .produce
        default:
            return .other
        }
    }

    // MARK: - Helpers

    private func lockKnownAliases(_ tokens: inout [String]) {
        // Try the longest tail match, so "caster sugar" beats "sugar".
        let joined = tokens.joined(separator: " ")
        if Self.aliases[joined] != nil { return }
        for length in stride(from: tokens.count - 1, through: 2, by: -1) {
            let suffix = tokens.suffix(length).joined(separator: " ")
            if Self.aliases[suffix] != nil {
                tokens = Array(tokens.prefix(tokens.count - length)) + [suffix]
                return
            }
        }
    }

    private func stripPunctuation(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "'’\"."))
    }

    private func singular(_ word: String) -> String {
        let keep: Set<String> = [
            "couscous", "asparagus", "hummus", "molasses", "swiss", "greens",
            "oats", "rice", "pasta", "chickpea", "quinoa", "semolina", "tahini",
            "sriracha", "salsa", "pesto", "mayonnaise", "yogurt", "cress",
        ]
        if keep.contains(word) || word.count <= 3 { return word }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("leaves") { return String(word.dropLast(6)) + "leaf" }
        if word.hasSuffix("loaves") { return String(word.dropLast(6)) + "loaf" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ches") || word.hasSuffix("shes")
            || word.hasSuffix("sses") || word.hasSuffix("xes") || word.hasSuffix("zes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }
}
