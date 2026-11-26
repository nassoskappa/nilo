import AppKit
import SwiftUI
import NiloCore
import NiloUI

/// The plan card: every step Nilo will take, before it acts. Each message is shown word for word
/// with everyone it goes to, so one yes covers the plan. Then it shows progress, and Undo.
struct PlanCard: Equatable {
    enum Phase: Equatable {
        /// Waiting for Do it or Cancel.
        case asking
        case running
        /// Finished. The text says what happened, result first.
        case finished(String)
        /// Cancelled, or stopped part way. The text says why.
        case stopped(String)
        case undone(String)
    }

    enum Status: Equatable {
        case waiting, working, done, skipped
        case failed(String)
    }

    struct Step: Equatable {
        var preview: StepPreview
        var status: Status = .waiting
    }

    var title: String
    var steps: [Step]
    var phase: Phase = .asking
    var canUndo = false

    init(title: String, steps: [StepPreview]) {
        self.title = title
        self.steps = steps.map { Step(preview: $0) }
    }

    mutating func set(_ id: String, _ status: Status) {
        guard let i = steps.firstIndex(where: { $0.preview.id == id }) else { return }
        steps[i].status = status
    }

    /// Steps that never got their turn.
    mutating func skipRest() {
        for i in steps.indices where steps[i].status == .waiting || steps[i].status == .working {
            steps[i].status = .skipped
        }
    }

    /// "Done. Tap Send in Messages." The last word goes to the person when an app is waiting.
    var doneText: String {
        let tools = Set(steps.map(\.preview.toolName))
        if tools.contains(WhatsAppComposeTool.name) && tools.contains(MessagesComposeTool.name) {
            return "Done. Tap Send in Messages and WhatsApp."
        }
        if tools.contains(WhatsAppComposeTool.name) { return "Done. Tap Send in WhatsApp." }
        if tools.contains(MessagesComposeTool.name) { return "Done. Tap Send in Messages." }
        return "Done."
    }
}

struct PlanCardView: View {
    var card: PlanCard
    var onDoIt: () -> Void
    var onCancel: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PlanCardLayout.rowGap) {
            Text(card.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                row(index, step)
            }
            footer
                .frame(height: PlanCardLayout.footer, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ index: Int, _ step: PlanCard.Step) -> some View {
        let preview = step.preview.preview
        return HStack(alignment: .firstTextBaseline, spacing: PlanCardLayout.markerGap) {
            marker(index, step.status)
                .frame(width: PlanCardLayout.marker, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(.body)
                    .foregroundStyle(step.status == .skipped ? .white.opacity(0.45) : .white)
                ForEach(PlanCardLayout.lines(preview), id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let text = preview.text {
                    // Word for word: this is what will be sent.
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
                if case .failed(let why) = step.status {
                    Text(why)
                        .font(.body)
                        .foregroundStyle(NiloColor.needsYou)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusWords(step.status))
    }

    /// Step numbers are counters, so they use SF Mono. A tick or a cross only once something happened.
    @ViewBuilder
    private func marker(_ index: Int, _ status: PlanCard.Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(NiloColor.signature)
        case .failed:
            Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(NiloColor.needsYou)
        case .working:
            Text("\(index + 1)").font(NiloFont.mono(13, weight: .bold)).foregroundStyle(NiloColor.signature)
        case .waiting, .skipped:
            Text("\(index + 1)").font(NiloFont.mono(13)).foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch card.phase {
        case .asking:
            HStack(spacing: 16) {
                Button(action: onDoIt) {
                    // An amber fill always takes the dark label colour (brand rule).
                    Text("Do it")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NiloColor.onSignature)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(NiloColor.signature, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Return")
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHint("Escape")
            }
        case .running:
            Text("Working")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
        case .finished(let text), .stopped(let text):
            HStack(spacing: 16) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.white)
                if card.canUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.plain)
                        .font(.body.weight(.medium))
                        .foregroundStyle(NiloColor.signature)
                        .accessibilityHint("Takes back the changes from this plan")
                }
            }
        case .undone(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
        }
    }

    private func statusWords(_ status: PlanCard.Status) -> String {
        switch status {
        case .waiting: "Not started"
        case .working: "Working"
        case .done: "Done"
        case .skipped: "Not run"
        case .failed(let why): "Failed: \(why)"
        }
    }
}

/// Measures the card up front, so the window never has to ask SwiftUI (AppKit layout loops).
enum PlanCardLayout {
    static let marker: CGFloat = 16
    static let markerGap: CGFloat = 8
    static let rowGap: CGFloat = 8
    static let footer: CGFloat = 30

    /// Detail lines under a step's title: its details, then who it goes to, then the items.
    static func lines(_ preview: ToolPreview) -> [String] {
        var lines = preview.details
        if !preview.recipients.isEmpty { lines.append("To \(preview.recipients.joined(separator: ", "))") }
        lines += preview.items
        return lines
    }

    static func height(_ card: PlanCard) -> CGFloat {
        let stepWidth = ApprovalLayout.width - marker - markerGap
        var total = ApprovalLayout.measure(card.title, .title3, width: ApprovalLayout.width) + rowGap
        for step in card.steps {
            let p = step.preview.preview
            var row = ApprovalLayout.measure(p.title, .body, width: stepWidth)
            for line in lines(p) { row += ApprovalLayout.measure(line, .body, width: stepWidth) + 2 }
            if let text = p.text { row += ApprovalLayout.measure("\u{201C}\(text)\u{201D}", .body, width: stepWidth) + 2 }
            if case .failed(let why) = step.status { row += ApprovalLayout.measure(why, .body, width: stepWidth) + 2 }
            total += row + rowGap
        }
        return total + footer + 10
    }
}
