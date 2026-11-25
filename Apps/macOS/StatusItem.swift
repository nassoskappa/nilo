import AppKit
import NiloUI

/// Nilo's icon in the menu bar. Click opens or closes the notch panel. Right-click (or
/// Control-click) shows a small menu: Open Nilo (with its global shortcut) and Quit. The image
/// comes from `MenuBarMark`, so it moves with the same motion as the ring in the panel.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onToggle: () -> Void

    init(mark: MenuBarMark, shortcut: GlobalShortcut.Combo?, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        super.init()

        // Shows the shortcut, so it's easy to discover.
        let open = menu.addItem(withTitle: "Open Nilo", action: #selector(openFromMenu), keyEquivalent: shortcut?.keyEquivalent ?? "")
        open.keyEquivalentModifierMask = shortcut?.menuModifiers ?? []
        open.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nilo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        if let button = item.button {
            button.image = mark.image
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Nilo")
        }
        mark.onImage = { [weak self] image in
            self?.item.button?.image = image
        }
    }

    @objc private func openFromMenu() {
        onToggle()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onToggle()
        }
    }
}
