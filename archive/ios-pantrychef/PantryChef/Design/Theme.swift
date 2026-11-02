import SwiftUI

enum Theme {
    static let background = Color(hex: 0xFFF7EF)
    static let surface = Color.white
    static let accent = Color(hex: 0xE4572E)
    static let accentSoft = Color(hex: 0xFDE6DB)
    static let ink = Color(hex: 0x2B2018)
    static let muted = Color(hex: 0x8A7A6D)
    static let hairline = Color(hex: 0xEDE0D3)
    static let good = Color(hex: 0x3F8F5B)
    static let goodSoft = Color(hex: 0xE4F2E8)
    static let missing = Color(hex: 0xB08A6A)

    static let cardRadius: CGFloat = 18
    static let screenPadding: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    func cardSurface() -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}
