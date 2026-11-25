import Foundation
import Testing
@testable import NiloUI

@Suite("Done: the loop closes")
struct DoneMotionTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func motion(_ profile: MarkProfile, reduceMotion: Bool = false) -> MarkMotion {
        MarkMotion(state: .done, profile: profile, reduceMotion: reduceMotion, start: start)
    }

    @Test(arguments: [MarkProfile.panel, .menuBar])
    func restsAsAPlainBar(profile: MarkProfile) {
        let m = motion(profile)
        let f = m.frame(at: m.settledDate)
        #expect(f.turn == 0)
        #expect(f.lap == 0)
        #expect(f.dim == 0)
        #expect(f.flare == 0)
    }

    @Test func lapIsGoneBeforeTheTurnBack() {
        let m = motion(.panel)
        // Step through the whole sequence: whenever the ring is turning away, no lap is drawn.
        var t = 0.0
        while t <= m.settleDuration {
            let f = m.frame(at: start.addingTimeInterval(t))
            if f.turn < 1 { #expect(f.lap == 0, "lap still drawn at \(t)s while turning") }
            t += 0.01
        }
    }

    @Test func lapDrawsOnce() {
        let m = motion(.panel)
        let laps = stride(from: 0.0, through: m.settleDuration, by: 0.01)
            .map { m.frame(at: start.addingTimeInterval($0)).lap }
        #expect(laps.contains { $0 > 0.4 && $0 < 0.6 })
        #expect(laps.contains(1))
    }

    @Test func reduceMotionHasNoLap() {
        let m = motion(.panel, reduceMotion: true)
        let laps = stride(from: 0.0, through: m.settleDuration, by: 0.01)
            .map { m.frame(at: start.addingTimeInterval($0)).lap }
        #expect(laps.allSatisfy { $0 == 0 })
    }
}
