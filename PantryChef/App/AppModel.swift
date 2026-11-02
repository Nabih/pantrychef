import Foundation
import Observation
import PantryCore

/// Observable app state. Owns the catalog, the pantry selection and the
/// pre-computed recipe index.
@Observable
@MainActor
final class AppModel {
    enum LoadState {
        case ready
        case failed(String)
    }

    private(set) var options: [IngredientOption] = []
    private(set) var index: RecipeIndex?
    private(set) var state: LoadState = .ready
    private(set) var attribution = ""

    var selected: Set<String> = []
    private(set) var results: [RecipeMatch] = []

    private static let selectionKey = "pantry.selection.v1"

    init() {
        do {
            let catalog = try CatalogLoader.loadBundled()
            attribution = catalog.attribution
            options = catalog.ingredientOptions().filter { !$0.isStaple }
            index = RecipeIndex(meals: catalog.meals)

            let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []
            let known = Set(options.map(\.raw))
            selected = Set(stored.filter { known.contains($0) })
            recompute()
        } catch {
            state = .failed(
                "The recipe catalog could not be loaded. Run `python3 Tools/build_catalog.py` to generate it."
            )
        }
    }

    // MARK: - Selection

    func isSelected(_ option: IngredientOption) -> Bool {
        selected.contains(option.raw)
    }

    func toggle(_ option: IngredientOption) {
        if selected.contains(option.raw) {
            selected.remove(option.raw)
        } else {
            selected.insert(option.raw)
        }
        recompute()
    }

    func remove(_ raw: String) {
        selected.remove(raw)
        recompute()
    }

    func clear() {
        selected.removeAll()
        recompute()
    }

    private func recompute() {
        results = index?.rank(pantry: selected, minimumScore: 0.01) ?? []
        UserDefaults.standard.set(Array(selected), forKey: Self.selectionKey)
    }

    // MARK: - Lookups

    func selectedOptions() -> [IngredientOption] {
        options
            .filter { selected.contains($0.raw) }
            .sorted { $0.mealCount > $1.mealCount }
    }

    func visibleOptions(query: String, group: IngredientGroup?) -> [IngredientOption] {
        var pool = options

        if let group {
            pool = pool.filter { $0.group == group }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            pool = pool.filter { $0.display.localizedCaseInsensitiveContains(trimmed) }
        } else if group == nil {
            pool = Array(pool.prefix(48))
        } else {
            pool = Array(pool.prefix(60))
        }

        return pool
    }

    var cookableCount: Int {
        results.filter(\.isCookableNow).count
    }
}
