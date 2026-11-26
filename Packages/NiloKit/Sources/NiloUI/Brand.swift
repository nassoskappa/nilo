import SwiftUI

/// Nilo's colours. One amber on every background, dark or light. No dark or desaturated variant.
///
/// Rules:
/// - Amber is a shape or a surface. On black, amber marks, glow and text are all fine.
/// - On a light background amber is never text. There it is a fill with `onSignature` text on
///   top (about 11:1); links and small text use the system label colours.
/// - Any button with an amber fill uses `onSignature` for its label. SwiftUI's default white
///   text on amber is unreadable.
/// - Where Apple sets the tint (menu bar, tinted icons, Lock Screen widgets) the mark is monochrome.
/// - Never draw an amber or orange dot: macOS uses one to say a microphone is on. Nilo only
///   draws its own shapes, the bar and the ring.
public enum NiloColor {
    /// Signature amber.
    public static let signature = Color(hex: 0xFFB000)
    /// "Needs you": a lighter amber.
    public static let needsYou = Color(hex: 0xFFD27A)
    /// Text on an amber fill.
    public static let onSignature = Color(hex: 0x1A1000)
    /// Warm off-white for the wordmark's letters on black.
    public static let paper = Color(hex: 0xEDEBE4)
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
