import AppKit
import NiloUI

/// Nilo's menu bar icon.
///
/// Drawn in code as a template image, so macOS tints it black or white to
/// match the menu bar (brand rule: where Apple sets the tint, the mark is
/// monochrome).
///
/// It uses the character's two shapes (see "Character and motion" in CLAUDE.md):
/// - side-on, a short rounded bar: Nilo faces the task
/// - face-on, a small ring: Nilo faces you
///
/// The shapes swap with no animation. Apple discourages moving menu bar icons,
/// and the animated turn belongs in the panel.
enum MenuBarIcon {
    static func image(for state: MarkState) -> NSImage {
        let showRing = facesYou(state)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            if showRing {
                // The ring: 12 pt across, 2.6 pt line.
                let diameter: CGFloat = 12
                let line: CGFloat = 2.6
                let ringRect = NSRect(
                    x: (rect.width - diameter) / 2,
                    y: (rect.height - diameter) / 2,
                    width: diameter,
                    height: diameter
                ).insetBy(dx: line / 2, dy: line / 2)
                let ring = NSBezierPath(ovalIn: ringRect)
                ring.lineWidth = line
                ring.stroke()
            } else {
                // The cursor: 3.6 pt wide, 14 pt tall, fully rounded ends.
                let width: CGFloat = 3.6
                let height: CGFloat = 14
                let barRect = NSRect(
                    x: (rect.width - width) / 2,
                    y: (rect.height - height) / 2,
                    width: width,
                    height: height
                )
                NSBezierPath(roundedRect: barRect, xRadius: width / 2, yRadius: width / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nilo, \(state.label)"
        return image
    }

    /// Face-on when attention is on the person: listening, needs you, done.
    static func facesYou(_ state: MarkState) -> Bool {
        switch state {
        case .listening, .needsYou, .done: true
        case .idle, .thinking, .working, .noted: false
        }
    }
}
