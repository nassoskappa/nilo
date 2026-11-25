import AppKit
import SwiftUI
import NiloCore
import NiloUI

/// Phase 0 shell: a menu bar app that shows the mark and cycles its states.
/// Phase 1 replaces the menu with a panel attached to the notch.
@main
struct NiloApp: App {
    @State private var state: MarkState = .idle

    var body: some Scene {
        MenuBarExtra {
            StatePicker(state: $state)
        } label: {
            // Monochrome template: a bar when Nilo faces the task, a ring when it faces you.
            Image(nsImage: MenuBarIcon.image(for: state))
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatePicker: View {
    @Binding var state: MarkState

    var body: some View {
        VStack(spacing: 20) {
            MarkView(state: state, level: 0.5, height: 44)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.black, in: .rect(cornerRadius: 16))

            Text(state.label.uppercased())
                .font(NiloFont.mono(11))
                .tracking(1)
                .foregroundStyle(NiloColor.needsYou)

            HStack {
                Button("Previous") { step(-1) }
                Button("Next") { step(1) }
                    .keyboardShortcut(.space, modifiers: [])
            }

            Divider()
            Button("Quit Nilo") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(20)
        .frame(width: 280)
    }

    private func step(_ delta: Int) {
        let all = MarkState.allCases
        let index = all.firstIndex(of: state) ?? 0
        state = all[(index + delta + all.count) % all.count]
    }
}
