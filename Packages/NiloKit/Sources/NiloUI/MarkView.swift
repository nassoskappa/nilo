import SwiftUI

/// The living cursor. Seven states, one colour. Motion carries the meaning.
public enum MarkState: String, CaseIterable, Sendable, Identifiable {
    case idle, listening, thinking, working, needsYou, done, noted
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .noted: "Noted"
        }
    }
}

/// Starting point for Phase 1. Timings follow the canvas; tune them by feel.
public struct MarkView: View {
    public var state: MarkState
    /// Microphone level, 0...1. Drives the listening width.
    public var level: Double
    /// Height of the mark in points. Width scales from it.
    public var height: CGFloat

    public init(state: MarkState, level: Double = 0, height: CGFloat = 34) {
        self.state = state
        self.level = level
        self.height = height
    }

    private var baseWidth: CGFloat { height * 0.3 }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                if state == .working {
                    workingBar(t)
                } else {
                    RoundedRectangle(cornerRadius: baseWidth / 2, style: .continuous)
                        .fill(state == .needsYou ? NiloColor.needsYou : NiloColor.signature)
                        .frame(width: width(t), height: height)
                        .scaleEffect(x: scaleX(t), y: scaleY(t))
                        .offset(y: hop(t))
                        .opacity(opacity(t))
                        .shadow(color: NiloColor.signature.opacity(0.8), radius: glow(t))
                }
            }
            .frame(width: height * 2.4, height: height * 1.4)
        }
        .accessibilityElement()
        .accessibilityLabel("Nilo")
        .accessibilityValue(state.label)
    }

    // MARK: - Motion

    /// Repeating 0...1 phase for a period in seconds.
    private func phase(_ t: TimeInterval, period: Double) -> Double {
        (t.truncatingRemainder(dividingBy: period)) / period
    }

    private func width(_ t: TimeInterval) -> CGFloat {
        guard state == .listening else { return baseWidth }
        // Width is the voice. Clamp so silence still shows a thin mark.
        return baseWidth + CGFloat(min(max(level, 0), 1)) * height * 1.2
    }

    private func opacity(_ t: TimeInterval) -> Double {
        switch state {
        case .idle:
            // Slow blink: on, fade, off, back. Period 2.8 s.
            let p = phase(t, period: 2.8)
            if p < 0.4 { return 1 }
            if p < 0.55 { return 1 - (p - 0.4) / 0.15 * 0.82 }
            if p < 0.9 { return 0.18 }
            return 0.18 + (p - 0.9) / 0.1 * 0.82
        case .thinking:
            return 0.65 + 0.35 * breathe(t, period: 2.2)
        default:
            return 1
        }
    }

    private func scaleX(_ t: TimeInterval) -> CGFloat {
        switch state {
        case .thinking: 1 + 1.2 * CGFloat(breathe(t, period: 2.2))
        case .noted: 1 + 0.25 * CGFloat(pulse(t, period: 3))
        default: 1
        }
    }

    private func scaleY(_ t: TimeInterval) -> CGFloat {
        guard state == .done else { return 1 }
        // A nod: squash, overshoot, settle. Then rest.
        let p = CGFloat(phase(t, period: 2.6))
        if p < 0.12 { return 1 - 0.65 * (p / 0.12) }
        if p < 0.24 { return 0.35 + 0.83 * ((p - 0.12) / 0.12) }
        if p < 0.34 { return 1.18 - 0.18 * ((p - 0.24) / 0.10) }
        return 1
    }

    private func hop(_ t: TimeInterval) -> CGFloat {
        guard state == .needsYou else { return 0 }
        let p = CGFloat(phase(t, period: 2.4))
        // One hop, a smaller one, then wait.
        if p < 0.06 { return -height * 0.26 * (p / 0.06) }
        if p < 0.12 { return -height * 0.26 * (1 - (p - 0.06) / 0.06) }
        if p < 0.18 { return -height * 0.12 * ((p - 0.12) / 0.06) }
        if p < 0.24 { return -height * 0.12 * (1 - (p - 0.18) / 0.06) }
        return 0
    }

    private func glow(_ t: TimeInterval) -> CGFloat {
        switch state {
        case .needsYou: height * 0.45
        case .noted: height * (0.25 + 0.5 * CGFloat(pulse(t, period: 3)))
        default: height * 0.3
        }
    }

    /// Smooth 0...1...0.
    private func breathe(_ t: TimeInterval, period: Double) -> Double {
        (sin(phase(t, period: period) * 2 * .pi - .pi / 2) + 1) / 2
    }

    /// One slow pulse per period, then rest.
    private func pulse(_ t: TimeInterval, period: Double) -> Double {
        let p = phase(t, period: period)
        guard p > 0.3, p < 0.7 else { return 0 }
        return sin((p - 0.3) / 0.4 * .pi)
    }

    private func workingBar(_ t: TimeInterval) -> some View {
        let track = height * 2.3
        let thumb = height * 0.55
        let barHeight = max(3, height * 0.12)
        let travel = CGFloat((sin(phase(t, period: 1.8) * 2 * .pi) + 1) / 2)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.12)).frame(width: track, height: barHeight)
            Capsule()
                .fill(NiloColor.signature)
                .frame(width: thumb, height: barHeight)
                .shadow(color: NiloColor.signature.opacity(0.8), radius: height * 0.2)
                .offset(x: (track - thumb) * travel)
        }
    }
}

#Preview("All states") {
    HStack(spacing: 24) {
        ForEach(MarkState.allCases) { state in
            VStack(spacing: 12) {
                MarkView(state: state, level: 0.5)
                Text(state.label).font(NiloFont.mono(11)).foregroundStyle(.secondary)
            }
        }
    }
    .padding(40)
    .background(Color.black)
}
