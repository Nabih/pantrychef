import PantryCore
import SwiftUI

struct RecipeDetailView: View {
    let match: RecipeMatch

    private enum Status {
        case have, need, staple
    }

    private var meal: Meal { match.meal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                titleBlock
                matchBanner
                ingredientSection
                stepsSection
                footer
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }

    // MARK: - Sections

    private var hero: some View {
        MealImage(url: meal.thumb, size: "large")
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meal.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if !meal.area.isEmpty {
                    pill(meal.area, symbol: "globe.europe.africa")
                }
                if !meal.category.isEmpty {
                    pill(meal.category, symbol: "fork.knife")
                }
                if !meal.steps.isEmpty {
                    pill("\(meal.steps.count) steps", symbol: "list.number")
                }
            }
        }
    }

    private func pill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }

    private var matchBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.isCookableNow
                     ? "You can cook this now"
                     : "You have \(match.matched.count) of \(match.totalRequired) ingredients")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(match.isCookableNow ? Theme.good : Theme.ink)
                Spacer()
                Text("\(Int((match.score * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(match.isCookableNow ? Theme.good : Theme.accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(match.isCookableNow ? Theme.good : Theme.accent)
                        .frame(width: max(6, proxy.size.width * match.score))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(match.isCookableNow ? Theme.goodSoft : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ingredients")
            VStack(spacing: 0) {
                ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { index, line in
                    ingredientRow(line)
                    if index < meal.ingredients.count - 1 {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .cardSurface()
        }
    }

    private func ingredientRow(_ line: IngredientLine) -> some View {
        let status = status(for: line)
        return HStack(spacing: 12) {
            Image(systemName: icon(for: status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: status))
                .frame(width: 20)

            Text(line.name)
                .font(.subheadline)
                .foregroundStyle(status == .need ? Theme.ink : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text(line.measure)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.name), \(line.measure), \(accessibilityStatus(status))")
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Method")
            ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.accent)
                        .clipShape(Circle())

                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.hairline)

            if let link = URL(string: meal.sourceUrl) {
                Link(destination: link) {
                    Label("View this recipe on TheMealDB", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if !meal.youtube.isEmpty, let youtube = URL(string: meal.youtube) {
                Link(destination: youtube) {
                    Label("Watch the video", systemImage: "play.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            Text("Recipe data and imagery: TheMealDB (themealdb.com)")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func status(for line: IngredientLine) -> Status {
        let normalizer = IngredientNormalizer.shared
        if normalizer.isStaple(line.name) { return .staple }
        let display = normalizer.canonical(line.name).display
        return match.missing.contains(display) ? .need : .have
    }

    private func icon(for status: Status) -> String {
        switch status {
        case .have: "checkmark.circle.fill"
        case .need: "circle.dashed"
        case .staple: "circle.fill"
        }
    }

    private func color(for status: Status) -> Color {
        switch status {
        case .have: Theme.good
        case .need: Theme.missing
        case .staple: Theme.hairline
        }
    }

    private func accessibilityStatus(_ status: Status) -> String {
        switch status {
        case .have: "in your pantry"
        case .need: "you need this"
        case .staple: "assumed pantry staple"
        }
    }
}
