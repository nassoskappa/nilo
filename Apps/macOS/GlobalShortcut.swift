import AppKit
import Carbon.HIToolbox
import os

/// A keyboard shortcut that works in every app, to call Nilo from anywhere.
///
/// Uses the system's hot key service, which works inside the App Store sandbox and needs no
/// Accessibility permission. The system swallows the key press, so the app you're in never
/// sees it.
@MainActor
final class GlobalShortcut {
    struct Combo: CustomStringConvertible {
        var keyCode: UInt32
        var modifiers: UInt32
        var name: String
        /// The same combo, as a menu shows it.
        var keyEquivalent: String
        var menuModifiers: NSEvent.ModifierFlags
        var description: String { name }

        static let optionSpace = Combo(
            keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), name: "⌥Space",
            keyEquivalent: " ", menuModifiers: [.option]
        )
        static let controlOptionSpace = Combo(
            keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), name: "⌃⌥Space",
            keyEquivalent: " ", menuModifiers: [.control, .option]
        )
    }

    /// The combo that was registered, or nil if every choice was taken.
    private(set) var combo: Combo?

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let log = Logger(subsystem: "nilo", category: "shortcut")

    /// Tries each combo in order and keeps the first one no other app has claimed.
    init(trying choices: [Combo], action: @escaping () -> Void) {
        self.action = action
        installHandler()
        for choice in choices {
            if register(choice) {
                combo = choice
                break
            }
            Self.log.notice("\(choice.name, privacy: .public) is taken by another app; trying the next one.")
        }
        if combo == nil {
            Self.log.error("No global shortcut available. Use the menu bar icon.")
        }
    }

    private func register(_ choice: Combo) -> Bool {
        let id = EventHotKeyID(signature: OSType(0x4E494C4F), id: 1) // "NILO"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(choice.keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKey = ref
        return true
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &spec, me, &handler)
    }
}
