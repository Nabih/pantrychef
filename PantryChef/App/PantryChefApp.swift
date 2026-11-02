import PantryCore
import SwiftUI

@main
struct PantryChefApp: App {
    @State private var model = AppModel()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .ready:
                    PantryView()
                case .failed(let message):
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Catalog missing",
                        message: message
                    )
                    .padding(Theme.screenPadding)
                }
            }
            .navigationDestination(for: ResultsPayload.self) { payload in
                ResultsView(matches: payload.matches)
            }
            .navigationDestination(for: RecipeMatch.self) { match in
                RecipeDetailView(match: match)
            }
        }
    }
}
