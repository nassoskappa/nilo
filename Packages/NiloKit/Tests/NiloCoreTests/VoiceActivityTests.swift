import Foundation
import Testing
@testable import NiloCore

@Suite("Voice activity")
struct VoiceActivityTests {
    /// RMS values for a loud voice and a quiet room.
    let speaking = 0.1    // -20 dB
    let quiet = 0.001     // -60 dB
    let step = 1.0 / 30

    /// Feed `rms` for `seconds`, starting at `from`. Returns the time the end was reported, if any.
    func feed(_ v: inout VoiceActivity, rms: Double, for seconds: Double, from: Double) -> Double? {
        var t = from
        var ended: Double?
        while t < from + seconds {
            if v.add(rms: rms, at: t) { ended = t }
            t += step
        }
        return ended
    }

    @Test func loudnessMapsDecibelsToZeroToOne() {
        #expect(VoiceActivity.loudness(rms: 0) == 0)
        #expect(VoiceActivity.loudness(rms: 0.001) == 0)  // -60 dB, below the floor
        #expect(VoiceActivity.loudness(rms: 1) == 1)      // 0 dB, above the ceiling
        let mid = VoiceActivity.loudness(rms: 0.01)       // -40 dB
        #expect(mid > 0.35 && mid < 0.5)
        #expect(VoiceActivity.loudness(rms: 0.1) == 1)    // -20 dB, ordinary speech fills it
    }

    @Test func silenceAloneNeverEnds() {
        var v = VoiceActivity()
        #expect(feed(&v, rms: quiet, for: 10, from: 0) == nil)
        #expect(!v.heardSpeech)
    }

    @Test func endsAboutOneSecondAfterSpeechStops() throws {
        var v = VoiceActivity()
        #expect(feed(&v, rms: speaking, for: 1, from: 0) == nil)
        #expect(v.heardSpeech)
        let ended = try #require(feed(&v, rms: quiet, for: 3, from: 1))
        #expect(ended >= 1 + 1.2 && ended < 1 + 1.3)
    }

    @Test func endIsReportedOnce() {
        var v = VoiceActivity()
        _ = feed(&v, rms: speaking, for: 1, from: 0)
        _ = feed(&v, rms: quiet, for: 2, from: 1)
        #expect(v.finished)
        #expect(feed(&v, rms: quiet, for: 2, from: 3) == nil)
    }

    @Test func aShortClickIsNotSpeech() {
        var v = VoiceActivity()
        _ = feed(&v, rms: speaking, for: 0.1, from: 0)
        #expect(feed(&v, rms: quiet, for: 3, from: 0.1) == nil)
    }

    @Test func aPauseBetweenWordsDoesNotEnd() {
        var v = VoiceActivity()
        _ = feed(&v, rms: speaking, for: 0.5, from: 0)
        #expect(feed(&v, rms: quiet, for: 0.8, from: 0.5) == nil)
        #expect(feed(&v, rms: speaking, for: 0.5, from: 1.3) == nil)
    }

    @Test func levelRisesFastAndFallsSlowly() {
        var v = VoiceActivity()
        _ = feed(&v, rms: speaking, for: 0.1, from: 0)
        #expect(v.level > 0.6)
        _ = feed(&v, rms: quiet, for: 0.1, from: 0.1)
        #expect(v.level > 0.3)  // still settling
        _ = feed(&v, rms: quiet, for: 1.5, from: 0.2)
        #expect(v.level < 0.05)
    }
}
