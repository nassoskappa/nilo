import Foundation

/// Turns raw microphone loudness into a calm 0...1 level for the ring, and decides when the
/// person has finished speaking. Pure: feed it samples with their times. No audio in here, and
/// nothing is kept: only loudness goes in.
public struct VoiceActivity: Sendable {
    /// Every number in one place. Tune here.
    public struct Tuning: Sendable {
        /// Quieter than this counts as silence (level 0). Louder than the ceiling is level 1.
        /// A laptop mic hears normal speech at about -35 to -20 dB, so ordinary talking reaches
        /// the top of the range.
        public var floorDB = -55.0
        public var ceilingDB = -26.0
        /// How fast the level rises and falls, in seconds. Fast up, slow down: no jitter.
        public var attack = 0.03
        public var release = 0.12
        /// Loudness that counts as speech, and loudness that counts as quiet.
        /// About -40 dB and -45 dB.
        public var speechLevel = 0.50
        public var quietLevel = 0.33
        /// Speech must last this long before Nilo waits for the end (ignores a cough or a click).
        public var minSpeech = 0.25
        /// Quiet for this long after speech means "they've finished".
        public var endAfterSilence = 1.2

        public init() {}
    }

    public let tuning: Tuning
    /// Smoothed level for drawing, 0...1.
    public private(set) var level = 0.0
    /// True once the person has said something.
    public private(set) var heardSpeech = false
    /// True once the end has been reported. It is reported only once.
    public private(set) var finished = false

    private var speech = 0.0
    private var quietSince: Double?
    private var lastTime: Double?

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Loudness 0...1 from the RMS of a buffer of samples.
    public static func loudness(rms: Double, tuning: Tuning = Tuning()) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db - tuning.floorDB) / (tuning.ceilingDB - tuning.floorDB), 0), 1)
    }

    /// Add one measurement. `time` is in seconds on any steady clock.
    /// Returns true once: at the moment the person has finished speaking.
    @discardableResult
    public mutating func add(rms: Double, at time: Double) -> Bool {
        let loud = Self.loudness(rms: rms, tuning: tuning)
        let dt = lastTime.map { max(time - $0, 0) } ?? 0
        lastTime = time

        // The level the ring draws: rises fast, falls slowly.
        let tau = loud > level ? tuning.attack : tuning.release
        if dt > 0 { level += (loud - level) * (1 - exp(-dt / tau)) }

        // Speech and quiet are judged on the raw loudness, so the wait starts the moment they stop.
        if loud >= tuning.speechLevel {
            speech += dt
            if speech >= tuning.minSpeech { heardSpeech = true }
            quietSince = nil
        } else if loud < tuning.quietLevel {
            if quietSince == nil { quietSince = time }
        } else {
            quietSince = nil
        }

        guard heardSpeech, !finished, let quiet = quietSince, time - quiet >= tuning.endAfterSilence else {
            return false
        }
        finished = true
        return true
    }
}
