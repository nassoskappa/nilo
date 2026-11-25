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
    /// Done: how far the ring is dimmed to about 18 %. 0 = normal, 1 = dimmed.
    public var dim = 0.0
    /// Done: how far the bright stroke has drawn round the ring, 0...1, from 12 o'clock, clockwise.
    public var lap = 0.0
    /// Done: the flare when the loop closes. 0 = none, 1 = full.
    public var flare = 0.0
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
    /// The state before this one. Leaving Listening ends with one blink.
    public let previous: MarkState?

    public init(
        state: MarkState,
        profile: MarkProfile,
        reduceMotion: Bool,
        start: Date = Date(),
        fromTurn: Double = 0,
        previous: MarkState? = nil
    ) {
        self.state = state
        self.profile = profile
        self.reduceMotion = reduceMotion
        self.start = start
        self.fromTurn = fromTurn
        self.previous = previous
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

    /// "Got it": when Listening ends, the ring blinks once before the next state begins.
    private var blinksFirst: Bool {
        previous == .listening && state != .listening && fromTurn > 0.9
    }

    /// Time the blink takes, plus a short beat, before the new state starts moving.
    private var blinkLead: Double { blinksFirst ? 0.08 + 0.12 + 0.06 : 0 }

    /// Seconds after `start` when a non-looping state has stopped moving.
    public var settleDuration: Double { blinkLead + stateSettle }

    private var stateSettle: Double {
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
        var lead, lapStart, lapTime, flare, back, end: Double
    }

    /// Done, once: turn to the person, dim the ring, one bright lap round it, flare when the
    /// loop closes, hold a beat, turn back.
    private var done: DoneTimes {
        let lead = abs(1 - fromTurn) < 0.01 ? 0 : turnTime
        let lapStart = lead + 0.15                    // the dim takes 150 ms
        let lapTime = reduceMotion ? 0.2 : 0.55       // Reduce Motion: no lap, a short hold
        let flare = lapStart + lapTime
        let back = flare + 0.15 + 0.35                // flare and settle 150 ms, then a beat
        return DoneTimes(lead: lead, lapStart: lapStart, lapTime: lapTime, flare: flare, back: back, end: back + turnTime)
    }

    // MARK: Frames

    public func frame(at now: Date) -> MarkFrame {
        let raw = max(0, now.timeIntervalSince(start))
        let t = max(0, raw - blinkLead)
        var f = MarkFrame()

        if blinksFirst {
            // Blink: close in 80 ms, open in 120 ms.
            let close = seg(raw, 0, 0.08)
            let open = seg(raw, 0.08, 0.12)
            f.blink = 1 - 0.92 * (close - open)
        }

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
            // The ring dims to about 18 % until the loop closes.
            f.dim = ease(seg(t, d.lead, 0.15)) - ease(seg(t, d.flare, 0.05))
            // One lap, clockwise from 12 o'clock. The only time light travels round the ring.
            // It ends once the loop has closed and the ring is back to full brightness, so the
            // stroke never stays behind when the ring turns back into the bar.
            if !reduceMotion, t < d.flare + 0.05 {
                f.lap = ease(seg(t, d.lapStart, d.lapTime))
            }
            // The loop closes: about 1.6x brightness and 6 % larger for 150 ms, then settle.
            f.flare = ease(seg(t, d.flare, 0.05)) - ease(seg(t, d.flare + 0.05, 0.10))
            f.glow = 1 + 1.2 * f.flare
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
