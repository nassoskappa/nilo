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
    /// Bumped by "Play again". Both the panel and the icon restart when it changes.
    private(set) var replay = 0
    private(set) var image: NSImage

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
        state = newState
        begin(snap: false)
    }

    func replayNow() {
        replay += 1
        begin(snap: true)
    }

    private func begin(snap: Bool) {
        let now = Date()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let from = snap ? 0 : motion.frame(at: now).turn
        motion = MarkMotion(state: state, profile: .menuBar, reduceMotion: reduce, start: now, fromTurn: from)
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
                self.image = self.render(frame, state: self.state, reduceMotion: reduceMotion)
                guard moving else { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func render(_ frame: MarkFrame, state: MarkState, reduceMotion: Bool) -> NSImage {
        let view = MarkFrameView(
            frame: frame,
            height: markHeight,
            color: .black,
            glow: false,
            reduceMotion: reduceMotion,
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
