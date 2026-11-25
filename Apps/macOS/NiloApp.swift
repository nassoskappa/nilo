import AppKit
import SwiftUI
import NiloCore
import NiloUI

/// Phase 1b: Nilo lives in the notch. The menu bar icon opens and closes the notch panel.
/// There are no ordinary windows, so the app is all AppKit underneath; SwiftUI draws the panel.
@main
struct NiloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A menu bar app needs one scene; this one never shows.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The one shared state. The menu bar icon and the panel's ring both read it.
    private let mark = MenuBarMark()
    private var panel: NotchPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanelController(mark: mark)
        self.panel = panel
        statusItem = StatusItemController(mark: mark) { panel.toggle() }

        #if DEBUG
        // For screenshots: `open Nilo.app --args -NiloOpenOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "NiloOpenOnLaunch") { panel.open() }
        #endif
    }
}
