import SwiftUI
import AppKit

// MARK: - Palette

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Pal {
    static let cream = Color(hex: 0xFFF7EC)
    static let card = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x5A4636)
    static let soft = Color(hex: 0xA8968A)
    static let line = Color(hex: 0xF1E4D3)
    static let coral = Color(hex: 0xFF8B7B)
    static let peach = Color(hex: 0xFFB37A)
    static let butter = Color(hex: 0xFFD66B)
    static let mint = Color(hex: 0x8FD6B4)
    static let sky = Color(hex: 0x9CC8F2)
    static let lilac = Color(hex: 0xC6B3F2)

    static func rank(_ i: Int) -> Color {
        [coral, peach, butter, mint, sky, lilac][min(i, 5)]
    }

    /// Tag dot colors, handed out in the order tags were first used.
    static let tagColors = [Color(hex: 0xF4A493), Color(hex: 0x8EC9A8), Color(hex: 0x9DBFE6), Color(hex: 0xF2C66D),
                            Color(hex: 0xC2AEEB), Color(hex: 0xEFA9CB), Color(hex: 0x8FCFD6), Color(hex: 0xD9B48F)]
}

extension Font {
    static func cute(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
