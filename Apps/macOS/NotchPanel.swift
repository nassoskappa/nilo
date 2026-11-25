import AppKit
import SwiftUI
import NiloUI

// Nilo lives in the notch. Called, the notch grows down into a black panel. Dismissed, it
// shrinks back up into the notch and disappears. On a screen without a notch the same panel
// drops from the top centre, under the menu bar.
//
// Rules:
// - Never steals focus: the panel can take key presses (Esc, Space) without making Nilo the
//   active app, so the app you're in stays in front and keeps its menu bar.
// - Opens on the screen under the pointer, on every Space, over full-screen apps.
// - Grows in about 350 ms with a soft spring, shrinks in about 250 ms. Reduce Motion: a fade.

// MARK: - Sizes

/// Every size the panel uses, worked out for one screen.
struct NotchGeometry: Equatable {
    /// The open panel, including the notch strip at the top.
    static let openSize = CGSize(width: 360, height: 120)
    /// Extra room in the window so the spring can overshoot without being cut off.
    static let margin = CGSize(width: 24, height: 16)

    var hasNotch: Bool
    /// The hardware notch. Zero on screens without one.
    var notch: CGSize
    /// Distance from the top of the screen to the top of the panel. Zero under a notch.
    var topInset: CGFloat

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notch = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            topInset = 0
        } else {
            hasNotch = false
            notch = .zero
            // Just under the menu bar (zero when it's hidden, as in a full-screen app).
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            topInset = menuBar + 6
        }
    }

    /// The outward curve where the notch meets the menu bar, like the notch's own shoulders.
    func shoulder(open: Bool) -> CGFloat {
        hasNotch ? (open ? 12 : 6) : 0
    }

    func bottomRadius(open: Bool) -> CGFloat {
        open ? 26 : (hasNotch ? 10 : 16)
    }

    func size(open: Bool) -> CGSize {
        if open { return Self.openSize }
        // Closed: exactly the notch, plus its shoulders. Without a notch: a small pill.
        return hasNotch
            ? CGSize(width: notch.width + 2 * shoulder(open: false), height: notch.height)
            : CGSize(width: 220, height: 44)
    }

    /// Where the window sits on the screen, in screen coordinates.
    func windowFrame(on screen: NSScreen) -> NSRect {
        let width = Self.openSize.width + Self.margin.width
        let height = Self.openSize.height + Self.margin.height
        let top = screen.frame.maxY - topInset
        return NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
    }
}

// MARK: - The shape

/// The notch, stretched. The top edge is flush with the top of the screen; the top corners
/// curve outward (the shoulders), the bottom corners are rounded. Without a notch, all four
/// corners are rounded.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottom: CGFloat
    var hasNotch: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottom) }
        set { shoulder = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        guard hasNotch else {
            return Path(roundedRect: rect, cornerRadius: min(bottom, h / 2, w / 2), style: .continuous)
        }
        let s = min(shoulder, w / 4, h / 2)
        let b = min(bottom, (w - 2 * s) / 2, h - s)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        // Left shoulder: curves in from the menu bar, then straight down.
        p.addArc(tangent1End: CGPoint(x: s, y: 0), tangent2End: CGPoint(x: s, y: h), radius: s)
        p.addArc(tangent1End: CGPoint(x: s, y: h), tangent2End: CGPoint(x: w, y: h), radius: b)
        p.addArc(tangent1End: CGPoint(x: w - s, y: h), tangent2End: CGPoint(x: w - s, y: 0), radius: b)
        // Right shoulder.
        p.addArc(tangent1End: CGPoint(x: w - s, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: s)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: - The view

@MainActor
@Observable
final class NotchPanelModel {
    /// Open or closed. Animating this is the whole grow and shrink.
    var expanded = false
    /// True from the moment the panel is ordered in until it has fully shrunk away. The ring
    /// only exists while this is true, so nothing redraws while the panel is hidden.
    var visible = false
    var reduceMotion = false
    var geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

struct NotchPanelView: View {
    var model: NotchPanelModel
    var mark: MenuBarMark

    var body: some View {
        let g = model.geometry
        // With Reduce Motion the shape stays full size and the whole panel fades.
        let open = model.expanded || model.reduceMotion
        let size = g.size(open: open)
        let shape = NotchShape(shoulder: g.shoulder(open: open), bottom: g.bottomRadius(open: open), hasNotch: g.hasNotch)
        let fades = model.reduceMotion || !g.hasNotch

        shape
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                if model.visible {
                    content(g)
                        .opacity(model.expanded ? 1 : 0)
                        // Content arrives just after the shape starts growing, and leaves first.
                        .animation(model.expanded ? .easeOut(duration: 0.2).delay(0.1) : .easeIn(duration: 0.1), value: model.expanded)
                }
            }
            .clipShape(shape)
            .opacity(fades && !model.expanded ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Always laid out at full size. The growing shape reveals it.
    private func content(_ g: NotchGeometry) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: g.notch.height)
            HStack(spacing: 14) {
                MarkView(state: mark.state, height: 34, replay: mark.replay)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mark.state.label.uppercased())
                        .font(NiloFont.mono(11))
                        .tracking(1)
                        .foregroundStyle(NiloColor.needsYou)
                    Text("Ask Nilo to…")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22 + g.shoulder(open: true))
            .frame(maxHeight: .infinity)
        }
        .frame(width: NotchGeometry.openSize.width, height: NotchGeometry.openSize.height)
    }
}

// MARK: - The window

/// A borderless panel above the menu bar that can take key presses without activating Nilo.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Opening and closing

@MainActor
final class NotchPanelController {
    private let mark: MenuBarMark
    private let model: NotchPanelModel
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Bumped on every open and close, so a late "order out" never hides a panel just reopened.
    private var generation = 0

    init(mark: MenuBarMark) {
        self.mark = mark
        model = NotchPanelModel(geometry: NotchGeometry(screen: .underPointer))
        let host = NSHostingView(rootView: NotchPanelView(model: model, mark: mark))
        host.sizingOptions = []
        panel.contentView = host
    }

    func toggle() {
        model.expanded ? close() : open()
    }

    func open() {
        generation += 1
        let gen = generation
        let screen = NSScreen.underPointer
        model.geometry = NotchGeometry(screen: screen)
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.expanded = false
        model.visible = true
        panel.setFrame(model.geometry.windowFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        panel.makeKey()
        startWatching()

        // Draw it closed once, then grow on the next turn.
        Task { @MainActor [weak self] in
            guard let self, self.generation == gen else { return }
            withAnimation(self.model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.18)) {
                self.model.expanded = true
            }
        }
    }

    func close() {
        guard model.expanded else { return }
        stopWatching()
        generation += 1
        let gen = generation
        let duration = model.reduceMotion ? 0.2 : 0.25
        withAnimation(model.reduceMotion ? .easeInOut(duration: duration) : .spring(duration: duration, bounce: 0)) {
            model.expanded = false
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            guard let self, self.generation == gen else { return }
            self.panel.orderOut(nil)
            self.model.visible = false
        }
    }

    // MARK: Watching for "close" and test keys

    private func startWatching() {
        stopWatching()

        // A click anywhere in another app closes it. (Clicks in Nilo's own icon toggle it.)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }

        // Keys reach Nilo only while the panel is open.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            let chars = event.charactersIgnoringModifiers?.lowercased()
            let shift = event.modifierFlags.contains(.shift)
            guard event.modifierFlags.isDisjoint(with: [.option, .control, .command]) else { return event }
            let handled = MainActor.assumeIsolated { self?.handleKey(code: code, chars: chars, shift: shift) ?? false }
            return handled ? nil : event
        }) { monitors.append(m) }

        // Switching apps, Spaces or screens closes it too.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Esc closes. Hidden test keys: Space next state, Shift-Space previous, R play again.
    private func handleKey(code: UInt16, chars: String?, shift: Bool) -> Bool {
        switch code {
        case 53: close()                          // Esc
        case 49: mark.step(shift ? -1 : 1)        // Space
        default:
            guard chars == "r" else { return false }
            mark.replayNow()
        }
        return true
    }
}

extension NSScreen {
    /// The screen the pointer is on, so Nilo opens where you are looking.
    static var underPointer: NSScreen {
        let point = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(point, $0.frame, false) } ?? main ?? screens[0]
    }
}
