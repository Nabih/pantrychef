import PantryCore
import SwiftUI

struct ResultsView: View {
    let matches: [RecipeMatch]

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case cookNow = "Cook now"
        case almost = "Almost"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .all

    private var filtered: [RecipeMatch] {
        switch filter {
        case .all:
            return matches
        case .cookNow:
            return matches.filter(\.isCookableNow)
        case .almost:
            return matches.filter { !$0.isCookableNow && $0.missing.count <= 2 }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                filterRow

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "takeoutbag.and.cup.and.straw",
                        title: "Nothing here yet",
                        message: filter == .cookNow
                            ? "Add a couple of missing ingredients, or check the Almost tab."
                            : "Add more ingredients to your pantry and try again."
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { match in
                            NavigationLink(value: match) {
                                RecipeCard(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(matches.count) recipes match your pantry")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(matches.isEmpty
                 ? "Pick ingredients to see matches."
                 : "Sorted by how much you already have.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 4)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    FilterChip(title: item.rawValue, isSelected: filter == item) {
                        withAnimation(.easeOut(duration: 0.15)) { filter = item }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
