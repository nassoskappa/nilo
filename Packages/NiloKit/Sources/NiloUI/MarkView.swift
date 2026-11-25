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

// MARK: - Drawing one frame

/// Draws a single frame of the mark. No clock inside: whoever owns the time passes a frame in.
/// The panel uses it inside a `TimelineView`; the menu bar renders it to a template image.
public struct MarkFrameView: View {
    var frame: MarkFrame
    var height: CGFloat
    var color: Color
    var glow: Bool
    var reduceMotion: Bool
    var swell: CGFloat
    var canvas: CGSize

    public init(
        frame: MarkFrame,
        height: CGFloat,
        color: Color,
        glow: Bool = true,
        reduceMotion: Bool = false,
        swell: CGFloat = 1,
        canvas: CGSize? = nil
    ) {
        self.frame = frame
        self.height = height
        self.color = color
        self.glow = glow
        self.reduceMotion = reduceMotion
        self.swell = swell
        self.canvas = canvas ?? CGSize(width: height * 2.4, height: height * 1.4)
    }

    public var body: some View {
        let working = frame.sweep != nil
        let blinkNorm = (frame.blink - 0.08) / 0.92

        ZStack {
            layers(dim: frame.dim, lap: frame.lap)
                .opacity(working ? 0.35 : 1)
            if let travel = frame.sweep {
                layers(dim: 0, lap: 0)
                    .mask(sweep(travel))
            }
        }
        .scaleEffect(swell)
        // The loop closes: 6 % larger, and (where there is colour) about 1.6x brighter.
        .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * frame.flare)
        .brightness(glow ? 0.3 * frame.flare : 0)
        .scaleEffect(x: frame.sx, y: frame.sy)
        // Blink: the ring closes flat. With Reduce Motion it dips in brightness instead.
        .scaleEffect(y: reduceMotion ? 1 : frame.blink)
        .offset(y: -frame.hop * height)
        .opacity(reduceMotion ? 0.3 + 0.7 * blinkNorm : frame.opacity)
        .shadow(color: glow ? NiloColor.signature.opacity(0.7) : .clear, radius: height * 0.28 * frame.glow)
        .frame(width: canvas.width, height: canvas.height)
    }

    /// The ring itself, dimmed to about 18 % during Done, plus the bright lap drawn over it.
    private func layers(dim: Double, lap: Double) -> some View {
        ZStack {
            shape
                .opacity(1 - 0.82 * dim)
            if lap > 0 {
                let d = height * RingGeometry.ringDiameter
                let line = height * RingGeometry.ringLine
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: lap)
                    .rotation(.degrees(-90)) // start at 12 o'clock, draw clockwise
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: d, height: d)
            }
        }
        .frame(width: height, height: height)
    }

    @ViewBuilder
    private var shape: some View {
        if reduceMotion {
            // Cross-fade between the two shapes instead of turning.
            ZStack {
                RingShape(turn: 0, height: height).fill(color, style: FillStyle(eoFill: true)).opacity(1 - frame.turn)
                RingShape(turn: 1, height: height).fill(color, style: FillStyle(eoFill: true)).opacity(frame.turn)
            }
        } else {
            RingShape(turn: CGFloat(frame.turn), height: height).fill(color, style: FillStyle(eoFill: true))
        }
    }

    /// Working: a bright stretch of the cursor, moving along its edge.
    private func sweep(_ travel: Double) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom))
            .frame(width: height, height: height * 0.55)
            .offset(y: CGFloat(travel - 0.5) * height * 0.85)
            .frame(width: height, height: height)
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
        _motion = State(initialValue: MarkMotion(state: state, profile: .panel, reduceMotion: false))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: MarkMotion
    /// False once a one-off motion has finished, so the view stops redrawing.
    @State private var running = true

    private var voice: CGFloat { CGFloat(min(max(level, 0), 1)) }

    /// While listening, the glow swells with the voice as well as the size, so the ring answers
    /// each syllable. The colour keeps its hue; only the light grows.
    private func voiced(_ frame: MarkFrame) -> MarkFrame {
        guard state == .listening else { return frame }
        var f = frame
        f.glow += 1.2 * Double(voice)
        return f
    }

    private var color: Color {
        state == .needsYou ? NiloColor.needsYou : NiloColor.signature
    }

    public var body: some View {
        TimelineView(.animation(paused: !running)) { timeline in
            MarkFrameView(
                frame: voiced(motion.frame(at: running ? timeline.date : motion.settledDate)),
                height: height,
                color: color,
                reduceMotion: reduceMotion,
                swell: state == .listening && !reduceMotion ? 1 + 0.35 * voice : 1
            )
            // Reduce Motion: the voice brightens the ring instead of swelling it.
            .brightness(state == .listening && reduceMotion ? 0.45 * voice : 0)
        }
        .animation(.easeOut(duration: 0.05), value: level)
        .onAppear { if motion.reduceMotion != reduceMotion { restart(snap: false, previous: nil) } }
        .onChange(of: state) { old, _ in restart(snap: false, previous: old) }
        .onChange(of: replay) { restart(snap: true, previous: nil) }
        .onChange(of: reduceMotion) { restart(snap: false, previous: nil) }
        .task(id: motion.start) { await settle() }
        .accessibilityElement()
        .accessibilityLabel("Nilo")
        .accessibilityValue(state.label)
    }

    /// Begin the current state's motion. A turn carries on from where the ring is now.
    private func restart(snap: Bool, previous: MarkState?) {
        let now = Date()
        let from = snap ? 0 : motion.frame(at: now).turn
        motion = MarkMotion(state: state, profile: .panel, reduceMotion: reduceMotion, start: now, fromTurn: from, previous: previous)
        running = true
    }

    /// Stop redrawing once a motion that ends has ended.
    private func settle() async {
        running = true
        guard !motion.isLooping else { return }
        try? await Task.sleep(for: .seconds(motion.settleDuration + 0.05))
        if !Task.isCancelled { running = false }
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
