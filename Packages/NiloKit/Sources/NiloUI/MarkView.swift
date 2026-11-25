import SwiftUI

/// The seven things Nilo can be doing. Motion carries the meaning.
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

// MARK: - Geometry

/// The one shape. `turn` 0 is side-on (the cursor bar), 1 is face-on (the ring).
/// The turn is faked: the width grows from a bar to a circle, and the line thins.
enum RingGeometry {
    /// Bar width, as a share of the mark's height (same proportion as the old cursor).
    static let barWidth: CGFloat = 0.30
    /// Face-on diameter, as a share of the height.
    static let ringDiameter: CGFloat = 0.82
    /// Face-on line width, as a share of the height.
    static let ringLine: CGFloat = 0.14
}

/// A ring drawn as a filled outline, so every measurement can animate with `turn`.
struct RingShape: Shape {
    var turn: CGFloat
    var height: CGFloat

    var animatableData: CGFloat {
        get { turn }
        set { turn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let barW = height * RingGeometry.barWidth
        let ringD = height * RingGeometry.ringDiameter
        let ringLine = height * RingGeometry.ringLine
        let width = barW + (ringD - barW) * turn
        let tall = height + (ringD - height) * turn
        let line = barW + (ringLine - barW) * turn
        // The centre line of the stroke. At turn 0 it has no width, so the stroke is the bar.
        let w = max(width - line, 0.001)
        let h = max(tall - line, 0.001)
        let centre = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        return Path(roundedRect: centre, cornerRadius: min(w, h) / 2)
            .strokedPath(StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - The mark

/// Nilo's character: a ring of light. Side-on it reads as the cursor, face-on it is a ring.
/// Side-on means Nilo faces the task. Face-on means Nilo faces you.
public struct MarkView: View {
    public var state: MarkState
    /// Microphone level, 0...1. Swells the ring while listening.
    public var level: Double
    /// Height of the mark in points. Everything scales from it.
    public var height: CGFloat
    /// Change this number to replay the current state's motion from the start.
    public var replay: Int

    public init(state: MarkState, level: Double = 0, height: CGFloat = 34, replay: Int = 0) {
        self.state = state
        self.level = level
        self.height = height
        self.replay = replay
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 = side-on, 1 = face-on.
    @State private var turn: CGFloat = 0
    /// Vertical scale of the blink. 1 = open, 0.08 = closed.
    @State private var blink: CGFloat = 1
    /// 0 = no smile, 1 = full smile.
    @State private var smile: Double = 0
    /// Start of the current loop, so a breath begins at rest.
    @State private var epoch = Date()
    @State private var lastReplay = 0

    private struct PlayKey: Equatable {
        var state: MarkState
        var replay: Int
    }

    private var breathPeriod: Double? {
        guard !reduceMotion else { return nil }
        switch state {
        case .idle: return 3.2
        case .thinking: return 2.2
        default: return nil
        }
    }

    private var color: Color {
        state == .needsYou ? NiloColor.needsYou : NiloColor.signature
    }

    public var body: some View {
        TimelineView(.animation(paused: breathPeriod == nil && !(state == .working && !reduceMotion))) { timeline in
            ring(at: timeline.date.timeIntervalSince(epoch))
        }
        .frame(width: height * 2.4, height: height * 1.4)
        .animation(.easeInOut(duration: 0.33), value: state)
        .task(id: PlayKey(state: state, replay: replay)) { await play() }
        .accessibilityElement()
        .accessibilityLabel("Nilo")
        .accessibilityValue(state.label)
    }

    // MARK: Drawing

    private func ring(at t: TimeInterval) -> some View {
        let b = breathPeriod.map { breathe(t, period: $0) } ?? 0
        let working = state == .working
        let blinkNorm = (blink - 0.08) / 0.92
        let swell = state == .listening ? 1 + 0.18 * CGFloat(min(max(level, 0), 1)) : 1

        return ZStack {
            layers(smile: smile)
                .opacity(working ? 0.35 : 1)
            if working {
                layers(smile: 0)
                    .mask(sweep(at: t))
            }
        }
        .scaleEffect(swell)
        .animation(.easeOut(duration: 0.1), value: level)
        // Idle and thinking: breathe about 1.06 wide by 0.96 tall.
        .scaleEffect(x: 1 + 0.06 * CGFloat(b), y: 1 - 0.04 * CGFloat(b))
        // Blink: the ring closes flat. With Reduce Motion it dips in brightness instead.
        .scaleEffect(y: reduceMotion ? 1 : blink)
        .opacity(reduceMotion ? 0.3 + 0.7 * Double(blinkNorm) : 1)
        .shadow(color: NiloColor.signature.opacity(0.7), radius: height * 0.28)
    }

    /// The ring itself, plus the smile arc when there is one.
    private func layers(smile: Double) -> some View {
        ZStack {
            shape
                // The top dims to 16 %. The whole ring stays visible.
                .opacity(1 - 0.84 * smile)
            if smile > 0 {
                let d = height * RingGeometry.ringDiameter
                let line = height * RingGeometry.ringLine
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 15.0 / 360, to: 165.0 / 360) // about 150 degrees, centred on the bottom
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: d, height: d)
                    .opacity(smile)
            }
        }
        .frame(width: height, height: height)
    }

    @ViewBuilder
    private var shape: some View {
        if reduceMotion {
            // Cross-fade between the two shapes instead of turning.
            ZStack {
                RingShape(turn: 0, height: height).fill(color, style: FillStyle(eoFill: true)).opacity(1 - turn)
                RingShape(turn: 1, height: height).fill(color, style: FillStyle(eoFill: true)).opacity(turn)
            }
        } else {
            RingShape(turn: turn, height: height).fill(color, style: FillStyle(eoFill: true))
        }
    }

    /// Working: a bright stretch of the cursor, moving along its edge.
    private func sweep(at t: TimeInterval) -> some View {
        let travel = CGFloat((sin(t / 1.6 * 2 * .pi - .pi / 2) + 1) / 2)
        return Rectangle()
            .fill(LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom))
            .frame(width: height, height: height * 0.55)
            .offset(y: (travel - 0.5) * height * 0.85)
            .frame(width: height, height: height)
    }

    /// Smooth 0...1...0 over a period, starting at rest.
    private func breathe(_ t: TimeInterval, period: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: period) / period
        return (sin(p * 2 * .pi - .pi / 2) + 1) / 2
    }

    // MARK: Sequencing

    /// Plays the motion for the current state. SwiftUI cancels it when the state changes.
    private func play() async {
        epoch = Date()
        if replay != lastReplay {
            lastReplay = replay
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                turn = 0
                blink = 1
                smile = 0
            }
        }
        if smile != 0 || blink != 1 {
            withAnimation(.easeOut(duration: 0.15)) {
                smile = 0
                blink = 1
            }
        }

        switch state {
        case .idle, .thinking, .working:
            _ = await step(turnTime) { turn = 0 }
        case .listening, .needsYou:
            _ = await step(turnTime) { turn = 1 }
        case .noted:
            guard await step(turnTime, { turn = 0 }) else { return }
            // A glance: a quarter turn and back.
            guard await step(0.14, { turn = 0.5 }) else { return }
            _ = await step(0.18) { turn = 0 }
        case .done:
            await playDone()
        }
    }

    /// Done, once: turn to the person, blink, smile, turn back and rest.
    private func playDone() async {
        guard await step(turnTime, { turn = 1 }) else { return }
        guard await pause(0.12) else { return }
        // Blink: close in 80 ms, open in 120 ms.
        guard await step(0.08, { blink = 0.08 }) else { return }
        guard await step(0.12, { blink = 1 }) else { return }
        guard await pause(0.1) else { return }
        // Smile: in 300 ms, hold 500 ms, out 350 ms.
        guard await step(0.3, { smile = 1 }) else { return }
        guard await pause(0.5) else { return }
        guard await step(0.35, { smile = 0 }) else { return }
        guard await pause(0.1) else { return }
        _ = await step(turnTime) { turn = 0 }
    }

    /// 330 ms with ease-in-out. Shorter when Reduce Motion cross-fades.
    private var turnTime: Double { reduceMotion ? 0.2 : 0.33 }

    /// Animates a change and waits for it. Returns false if the state changed meanwhile.
    private func step(_ seconds: Double, _ change: () -> Void) async -> Bool {
        withAnimation(.easeInOut(duration: seconds)) { change() }
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
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
