import Foundation

/// Where the mark is drawn. The menu bar is small and one colour, so it moves a little more
/// and does not glow, and Idle is completely still there.
public enum MarkProfile: Sendable {
    case panel, menuBar
}

/// One instant of the mark: every number a drawing needs. No time, no animation inside.
public struct MarkFrame: Sendable, Equatable {
    /// 0 = side-on (the cursor bar), 1 = face-on (the ring).
    public var turn = 0.0
    /// Vertical scale of the blink. 1 = open, 0.08 = closed.
    public var blink = 1.0
    /// 0 = no smile, 1 = full smile.
    public var smile = 0.0
    public var sx = 1.0
    public var sy = 1.0
    public var glow = 1.0
    public var opacity = 1.0
    /// Hop height as a share of the mark's height. Positive is up.
    public var hop = 0.0
    /// Working only: where the bright stretch sits along the bar, 0...1. Nil when not working.
    public var sweep: Double?

    public init() {}
}

/// The motion for one state, from the moment it began. Pure: ask for the frame at a time.
/// The panel and the menu bar icon both read this, so they always agree.
public struct MarkMotion: Sendable {
    public let state: MarkState
    public let profile: MarkProfile
    public let reduceMotion: Bool
    public let start: Date
    /// How face-on the mark was when this state began, so a turn continues smoothly.
    public let fromTurn: Double

    public init(state: MarkState, profile: MarkProfile, reduceMotion: Bool, start: Date = Date(), fromTurn: Double = 0) {
        self.state = state
        self.profile = profile
        self.reduceMotion = reduceMotion
        self.start = start
        self.fromTurn = fromTurn
    }

    // MARK: Timing

    /// 330 ms with ease-in-out. A shorter cross-fade with Reduce Motion.
    private var turnTime: Double { reduceMotion ? 0.2 : 0.33 }
    private let hopTime = 0.36
    private let hopHeight = 0.16
    /// The menu bar is tiny, so loops move 1.5 times as far there.
    private var amp: Double { profile == .menuBar ? 1.5 : 1 }

    /// True while the state keeps moving on its own, with no end.
    public var isLooping: Bool {
        guard !reduceMotion else { return false }
        switch state {
        case .idle: return profile == .panel
        case .thinking, .working, .listening: return true
        case .needsYou, .noted, .done: return false
        }
    }

    /// Seconds after `start` when a non-looping state has stopped moving.
    public var settleDuration: Double {
        switch state {
        case .idle, .thinking, .working, .listening: return turnTime
        case .needsYou: return turnTime + (reduceMotion ? 0 : hopTime)
        case .noted: return notedLead + 0.14 + 0.18
        case .done: return done.end
        }
    }

    /// A moment after everything has settled. Draw this when nothing is moving.
    public var settledDate: Date { start.addingTimeInterval(settleDuration + 1) }

    private var notedLead: Double { fromTurn > 0.01 ? turnTime : 0 }

    private struct DoneTimes {
        var lead, blink, smile, back, end: Double
    }

    /// Done: turn to the person, blink, smile, turn back. Played once.
    private var done: DoneTimes {
        let lead = abs(1 - fromTurn) < 0.01 ? 0 : turnTime
        let blink = lead + 0.12            // a short beat after the turn
        let smile = blink + 0.08 + 0.12 + 0.1
        let back = smile + 0.3 + 0.5 + 0.35 + 0.1
        return DoneTimes(lead: lead, blink: blink, smile: smile, back: back, end: back + turnTime)
    }

    // MARK: Frames

    public func frame(at now: Date) -> MarkFrame {
        let t = max(0, now.timeIntervalSince(start))
        var f = MarkFrame()

        switch state {
        case .idle:
            f.turn = turn(to: 0, at: t)
            if isLooping {
                // Slow breath at full brightness: the bar widens a little and the glow swells.
                let b = breathe(t, period: 3.2)
                f.sx = 1 + 0.35 * amp * b
                f.sy = 1 - 0.06 * amp * b
                f.glow = 1 + 0.5 * b
            }
        case .thinking:
            f.turn = turn(to: 0, at: t)
            if isLooping {
                // Quicker and deeper, with a soft brightness pulse. Never below 70 %.
                let b = breathe(t, period: 2.2)
                f.sx = 1 + 0.6 * amp * b
                f.sy = 1 - 0.08 * amp * b
                f.glow = 1 + 0.3 * b
                f.opacity = 0.7 + 0.3 * b
            }
        case .working:
            f.turn = turn(to: 0, at: t)
            f.sweep = reduceMotion ? 0.5 : (sin(t / 1.6 * 2 * .pi - .pi / 2) + 1) / 2
        case .listening:
            f.turn = turn(to: 1, at: t)
            if isLooping {
                // Slow pulse while it waits for the person.
                let b = breathe(t, period: 1.8)
                f.sx = 1 + 0.07 * amp * b
                f.sy = 1 + 0.07 * amp * b
                f.glow = 1 + 0.6 * b
            }
        case .needsYou:
            // Turns to the person, one small hop on arrival, then a still ring. No staring loop.
            f.turn = turn(to: 1, at: t)
            let h = t - turnTime
            if !reduceMotion, h > 0, h < hopTime {
                f.hop = hopHeight * sin(.pi * h / hopTime)
            }
        case .noted:
            // A glance: settle side-on, then a quarter turn and back.
            if t < notedLead {
                f.turn = turn(to: 0, at: t)
            } else {
                let g = t - notedLead
                f.turn = g < 0.14
                    ? 0.5 * ease(g / 0.14)
                    : 0.5 * (1 - ease(seg(g, 0.14, 0.18)))
            }
        case .done:
            let d = done
            if t < d.lead {
                f.turn = fromTurn + (1 - fromTurn) * ease(seg(t, 0, d.lead))
            } else if t < d.back {
                f.turn = 1
            } else {
                f.turn = 1 - ease(seg(t, d.back, turnTime))
            }
            // Blink: close in 80 ms, open in 120 ms.
            let close = seg(t, d.blink, 0.08)
            let open = seg(t, d.blink + 0.08, 0.12)
            f.blink = 1 - 0.92 * (close - open)
            // Smile: in 300 ms, hold 500 ms, out 350 ms.
            f.smile = ease(seg(t, d.smile, 0.3)) - ease(seg(t, d.smile + 0.3 + 0.5, 0.35))
        }
        return f
    }

    // MARK: Helpers

    private func turn(to target: Double, at t: Double) -> Double {
        fromTurn + (target - fromTurn) * ease(seg(t, 0, turnTime))
    }

    /// Progress 0...1 through a segment that starts at `start` and lasts `duration`.
    private func seg(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        guard duration > 0 else { return t >= start ? 1 : 0 }
        return min(max((t - start) / duration, 0), 1)
    }

    /// Ease-in-out.
    private func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    /// Smooth 0...1...0 over a period, starting at rest.
    private func breathe(_ t: Double, period: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: period) / period
        return (sin(p * 2 * .pi - .pi / 2) + 1) / 2
    }
}
