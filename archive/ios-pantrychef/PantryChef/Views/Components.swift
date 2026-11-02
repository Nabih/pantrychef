import PantryCore
import SwiftUI

// MARK: - Navigation payload

struct ResultsPayload: Hashable {
    let matches: [RecipeMatch]
}

// MARK: - Chips

struct IngredientChip: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let count, !isSelected {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .background(isSelected ? Theme.accent : Theme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RemovableChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(Theme.accent)
        .background(Theme.accentSoft)
        .clipShape(Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .background(isSelected ? Theme.ink : Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Match ring

struct MatchRing: View {
    let score: Double
    var size: CGFloat = 46

    private var color: Color {
        if score >= 1 { return Theme.good }
        if score >= 0.6 { return Theme.accent }
        return Theme.missing
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, score))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((score * 100).rounded()))%")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int(score * 100)) percent of ingredients available")
    }
}

// MARK: - Recipe card

struct RecipeCard: View {
    let match: RecipeMatch

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MealImage(url: match.meal.thumb, size: "medium")
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(match.meal.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text([match.meal.area, match.meal.category]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                if match.isCookableNow {
                    Label("Ready to cook", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.good)
                } else {
                    Text("Need: " + match.missing.prefix(3).joined(separator: ", ")
                        + (match.missing.count > 3 ? " +\(match.missing.count - 3)" : ""))
                        .font(.caption)
                        .foregroundStyle(Theme.missing)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)
            MatchRing(score: match.score)
        }
        .padding(12)
        .cardSurface()
    }
}

// MARK: - Image

struct MealImage: View {
    let url: String
    var size: String? = nil

    private var resolved: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: size.map { "\(url)/\($0)" } ?? url)
    }

    var body: some View {
        AsyncImage(url: resolved) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay(ProgressView().tint(Theme.muted))
            @unknown default:
                placeholder
            }
        }
        .background(Theme.accentSoft)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Theme.accentSoft
            Image(systemName: "fork.knife")
                .font(.title3)
                .foregroundStyle(Theme.accent.opacity(0.5))
        }
    }
}

// MARK: - Small bits

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(Theme.muted)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
