import PantryCore
import SwiftUI

struct PantryView: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var group: IngredientGroup?
    @FocusState private var searchFocused: Bool

    private var visible: [IngredientOption] {
        model.visibleOptions(query: query, group: group)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                searchField

                if !model.selected.isEmpty {
                    selectedTray
                }

                categoryRow
                ingredientGrid
                stapleNote
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Pantry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.selected.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { model.clear() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's in your kitchen?")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Pick the ingredients you have — we'll rank recipes by how close you are.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField("Search ingredients", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var selectedTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your pantry (\(model.selected.count))")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.selectedOptions()) { option in
                        RemovableChip(title: option.display) {
                            model.remove(option.raw)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Popular", isSelected: group == nil) {
                    group = nil
                }
                ForEach(IngredientGroup.allCases, id: \.self) { item in
                    FilterChip(title: item.title, isSelected: group == item) {
                        group = group == item ? nil : item
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var ingredientGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            if visible.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No ingredients match",
                    message: "Try a shorter word, like “chick” or “tom”."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(visible) { option in
                        IngredientChip(
                            title: option.display,
                            count: option.mealCount,
                            isSelected: model.isSelected(option)
                        ) {
                            model.toggle(option)
                        }
                    }
                }
            }
        }
    }

    private var stapleNote: some View {
        Text("Salt, pepper, oil and water are assumed to be in every kitchen.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
    }

    // MARK: - CTA

    private var ctaBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.hairline)
            NavigationLink(value: ResultsPayload(matches: model.results)) {
                HStack {
                    Text(model.selected.isEmpty
                         ? "Pick ingredients to start"
                         : "Show \(model.results.count) recipes")
                        .font(.headline)
                    Spacer()
                    if !model.selected.isEmpty {
                        Text("\(model.cookableCount) ready now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(model.selected.isEmpty ? Theme.muted : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .disabled(model.selected.isEmpty)
            .accessibilityHint("Opens ranked recipe matches")
        }
        .background(.ultraThinMaterial)
    }
}
