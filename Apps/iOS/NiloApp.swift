import SwiftUI
import NiloCore
import NiloUI

/// Phase 0 shell: the mark on black. Tap to cycle its states.
@main
struct NiloApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct ContentView: View {
    @State private var state: MarkState = .idle

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                MarkView(state: state, level: 0.5, height: 64)
                Text(state.label.uppercased())
                    .font(NiloFont.mono(13))
                    .tracking(1)
                    .foregroundStyle(NiloColor.needsYou)
                Spacer()
                Wordmark(size: 28)
                    .padding(.bottom, 24)
            }
        }
        .contentShape(.rect)
        .onTapGesture { next() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the next state")
    }

    private func next() {
        let all = MarkState.allCases
        let index = all.firstIndex(of: state) ?? 0
        state = all[(index + 1) % all.count]
    }
}
