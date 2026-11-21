import SwiftUI

/// Nilo's colours. Rule: bright cyan only ever touches black.
/// On light or glass surfaces, use `capsule` behind the mark, or `deep` for text and buttons.
public enum NiloColor {
    /// Signature. Only on black.
    public static let signature = Color(hex: 0x4EF2E5)
    /// "Needs you": brighter tint. Only on black.
    public static let needsYou = Color(hex: 0xA6FAF3)
    /// Light mode buttons, links, the mark on white. 4.8:1 on white.
    public static let deep = Color(hex: 0x00807A)
    /// Text on a signature-coloured button.
    public static let onSignature = Color(hex: 0x041413)
    /// The capsule that carries its own black on glass and light surfaces.
    public static let capsule = Color(hex: 0x0B0B0A)
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum NiloFont {
    /// The machine's voice: state labels, counters, the wordmark. Small doses only.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
