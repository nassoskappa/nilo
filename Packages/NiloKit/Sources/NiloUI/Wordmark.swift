import SwiftUI

/// `nilo` plus the mark. On black use `.signature`; on white use `.onLight`.
public struct Wordmark: View {
    public enum Rendering { case signature, onLight, monochrome }

    public var size: CGFloat
    public var rendering: Rendering

    public init(size: CGFloat = 40, rendering: Rendering = .signature) {
        self.size = size
        self.rendering = rendering
    }

    public var body: some View {
        HStack(spacing: size * 0.12) {
            Text("nilo")
                .font(NiloFont.mono(size))
                .tracking(-size * 0.04)
                .foregroundStyle(textColor)
            RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                .fill(markColor)
                .frame(width: size * 0.18, height: size * 0.85)
                .shadow(color: rendering == .signature ? NiloColor.signature.opacity(0.8) : .clear,
                        radius: size * 0.25)
        }
        .accessibilityElement()
        .accessibilityLabel("Nilo")
    }

    private var textColor: Color {
        switch rendering {
        case .signature: Color(hex: 0xEDEBE4)
        case .onLight: Color(hex: 0x141412)
        case .monochrome: .white
        }
    }

    private var markColor: Color {
        switch rendering {
        case .signature: NiloColor.signature
        case .onLight: NiloColor.deep
        case .monochrome: .white
        }
    }
}
