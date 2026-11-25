import AppKit
import SwiftUI
import NiloUI

/// Nilo's menu bar icon, and the clock that moves it.
///
/// The icon is the same character as the panel, drawn from the same motion (`MarkMotion`), so
/// the two always agree. It is a template image: macOS tints it black or white to match the
/// menu bar (brand rule: where Apple sets the tint, the mark is monochrome). So there is no
/// cyan and no glow here. Motion carries the state.
///
/// Rules (see "Character and motion" in CLAUDE.md):
/// - Idle is completely still.
/// - The icon only redraws while something is moving, about 30 times a second.
/// - With Reduce Motion it cross-fades and never loops.
@MainActor
@Observable
final class MenuBarMark {
    private(set) var state: MarkState = .idle
    /// Bumped by "Play again" (R in the panel). Both the panel and the icon restart when it changes.
    private(set) var replay = 0
    private(set) var image: NSImage
    /// Microphone level 0...1 while listening. The panel's ring and the icon both swell with it.
    var level = 0.0
    /// Called with every new image, so the status item can show it.
    @ObservationIgnored var onImage: ((NSImage) -> Void)?

    private var motion: MarkMotion
    private var loop: Task<Void, Never>?

    private let size = CGFloat(18)
    private let markHeight = CGFloat(14)

    init() {
        motion = MarkMotion(state: .idle, profile: .menuBar, reduceMotion: false)
        image = NSImage()
        image = render(motion.frame(at: motion.settledDate), state: .idle, reduceMotion: false)
    }

    func set(_ newState: MarkState) {
        guard newState != state else { return }
        let old = state
        state = newState
        begin(snap: false, previous: old)
    }

    /// Step through the states, for testing. Wraps round at either end.
    func step(_ delta: Int) {
        let all = MarkState.allCases
        let index = all.firstIndex(of: state) ?? 0
        set(all[(index + delta + all.count) % all.count])
    }

    func replayNow() {
        replay += 1
        begin(snap: true, previous: nil)
    }

    private func begin(snap: Bool, previous: MarkState?) {
        let now = Date()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let from = snap ? 0 : motion.frame(at: now).turn
        motion = MarkMotion(state: state, profile: .menuBar, reduceMotion: reduce, start: now, fromTurn: from, previous: previous)
        run(reduceMotion: reduce)
    }

    /// Redraw about 30 times a second while moving, then once more at rest, then stop.
    private func run(reduceMotion: Bool) {
        loop?.cancel()
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                let now = Date()
                let moving = self.motion.isLooping
                    || now.timeIntervalSince(self.motion.start) < self.motion.settleDuration
                let frame = self.motion.frame(at: moving ? now : self.motion.settledDate)
                let swell = self.state == .listening && !reduceMotion ? 1 + 0.4 * min(max(self.level, 0), 1) : 1
                self.image = self.render(frame, state: self.state, reduceMotion: reduceMotion, swell: swell)
                self.onImage?(self.image)
                guard moving else { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func render(_ frame: MarkFrame, state: MarkState, reduceMotion: Bool, swell: Double = 1) -> NSImage {
        let view = MarkFrameView(
            frame: frame,
            height: markHeight,
            color: .black,
            glow: false,
            reduceMotion: reduceMotion,
            swell: swell,
            canvas: CGSize(width: size, height: size)
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        image.accessibilityDescription = "Nilo, \(state.label)"
        return image
    }
}
