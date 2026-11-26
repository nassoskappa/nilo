import AppKit
import SwiftUI
import NiloCore
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
// - Opening means listening: the mic is on only while the ring faces you in Listening.

// MARK: - Sizes

/// Every size the panel uses, worked out for one screen.
struct NotchGeometry: Equatable {
    /// The open panel, including the notch strip at the top.
    static let openSize = CGSize(width: 360, height: 120)
    /// Extra height under the request for a reply or a notice. An approval needs more.
    static let replyHeight: CGFloat = 64
    static func openHeight(extra: CGFloat) -> CGFloat { openSize.height + extra }
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

    func size(open: Bool, extra: CGFloat = 0) -> CGSize {
        if open { return CGSize(width: Self.openSize.width, height: Self.openHeight(extra: extra)) }
        // Closed: exactly the notch, plus its shoulders. Without a notch: a small pill.
        return hasNotch
            ? CGSize(width: notch.width + 2 * shoulder(open: false), height: notch.height)
            : CGSize(width: 220, height: 44)
    }

    /// Where the window sits on the screen, in screen coordinates.
    func windowFrame(on screen: NSScreen, extra: CGFloat = 0) -> NSRect {
        let width = Self.openSize.width + Self.margin.width
        let height = Self.openHeight(extra: extra) + Self.margin.height
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
    /// What the person is typing.
    var draft = ""
    /// What the person is saying: settled words, then words still being worked out.
    var voiceSettled = ""
    var voicePending = ""
    var voiceText: String { joinWords(voiceSettled, voicePending) }
    /// Shown under the request. The panel grows to make room.
    var reply: Reply?

    enum Reply: Equatable {
        /// The job Nilo understood, in plain words: a headline and a few detail lines.
        /// (Acting on it comes with the plan card and the jobs.)
        case understood(String, [String])
        /// Nilo can't understand requests without Apple Intelligence.
        case modelOff(ReaderAvailability)
        /// The person said no to the microphone. Typing still works.
        case micOff
        /// No microphone, or it would not start. Typing still works.
        case micMissing
        /// The speech recognizer is fetching its language files (first use).
        case voicePreparing
        /// Speech to text isn't available for the Mac's language.
        case voiceUnsupported
        /// "Got it" came with no words.
        case notHeard
        /// What a job did, result first.
        case result(String)
        /// Nilo has no calendar access. Turn on opens Privacy settings.
        case calendarOff
        /// Nilo has no contacts access. Turn on opens Privacy settings.
        case contactsOff
        /// A send or delete waiting for the person: the exact text and everyone it goes to.
        case approval(StepPreview)

        var height: CGFloat {
            switch self {
            case .approval(let step): return ApprovalLayout.height(step.preview)
            case .understood(let headline, let details): return ApprovalLayout.height(headline: headline, details: details)
            default: return NotchGeometry.replyHeight
            }
        }
    }

    /// Height of the reply area, zero when there's none.
    var replyHeight: CGFloat { reply?.height ?? 0 }

    @ObservationIgnored var onType: () -> Void = {}
    @ObservationIgnored var onAnswer: (Bool) -> Void = { _ in }
    @ObservationIgnored var onSubmit: (String) -> Void = { _ in }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

struct NotchPanelView: View {
    @Bindable var model: NotchPanelModel
    var mark: MenuBarMark
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let g = model.geometry
        // With Reduce Motion the shape stays full size and the whole panel fades.
        let open = model.expanded || model.reduceMotion
        let size = g.size(open: open, extra: model.replyHeight)
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
            .onChange(of: model.expanded) { _, open in if open { fieldFocused = true } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Where the person types. Return sends.
    private var field: some View {
        TextField("", text: $model.draft, prompt: Text("Ask Nilo to…").foregroundStyle(.white.opacity(0.45)))
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundStyle(.white)
            .tint(NiloColor.signature)
            .focused($fieldFocused)
            .onSubmit { model.onSubmit(model.draft) }
            .onChange(of: model.draft) { _, text in if !text.isEmpty { model.onType() } }
            .accessibilityLabel("Ask Nilo")
    }

    private var showsVoice: Bool { model.draft.isEmpty && !model.voiceText.isEmpty }

    /// Live words: settled in white, words still being worked out in grey. The newest words
    /// stay in view.
    private var voiceLine: some View {
        let settled = model.voiceSettled
        let pending = model.voicePending
        let gap = settled.isEmpty || pending.isEmpty || settled.hasSuffix(" ") || pending.hasPrefix(" ") ? "" : " "
        return Text("\(Text(settled).foregroundStyle(.white))\(Text(gap + pending).foregroundStyle(.white.opacity(0.45)))")
            .font(.title3)
            .lineLimit(1)
            .truncationMode(.head)
            .accessibilityLabel("Heard: \(model.voiceText)")
    }

    @ViewBuilder
    private func replyView(_ reply: NotchPanelModel.Reply) -> some View {
        switch reply {
        case .understood(let headline, let details):
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        case .modelOff(let availability):
            switch availability {
            case .turnedOff:
                VStack(alignment: .leading, spacing: 2) {
                    notice("Turn on Apple Intelligence so Nilo can understand you.")
                    turnOnPane("com.apple.Siri-Settings.extension", hint: "Opens Apple Intelligence settings")
                }
            case .notReady:
                notice("Apple Intelligence is still getting ready. Try again in a few minutes.")
            case .unsupported, .ready:
                notice("Nilo needs Apple Intelligence, which this Mac doesn't have.")
            }
        case .micOff:
            VStack(alignment: .leading, spacing: 2) {
                notice("Microphone is off. You can type.")
                turnOn("Privacy_Microphone", hint: "Opens Privacy settings for the microphone")
            }
        case .calendarOff:
            VStack(alignment: .leading, spacing: 2) {
                notice("Nilo can't see your calendar.")
                turnOn("Privacy_Calendars", hint: "Opens Privacy settings for calendars")
            }
        case .contactsOff:
            VStack(alignment: .leading, spacing: 2) {
                notice("Nilo can't see your contacts.")
                turnOn("Privacy_Contacts", hint: "Opens Privacy settings for contacts")
            }
        case .approval(let step):
            approvalView(step)
        case .result(let text):
            Text(text)
                .font(.title3)
                .foregroundStyle(.white)
                .lineLimit(2)
        case .micMissing:
            notice("No microphone found. You can type.")
        case .voicePreparing:
            notice("Getting voice ready\u{2026} You can type.")
        case .voiceUnsupported:
            notice("Voice isn't available in your language yet. You can type.")
        case .notHeard:
            notice("Didn't catch that. Try again, or type.")
        }
    }

    /// A plain approval: who it goes to, the exact text, and two buttons. Return is yes, Esc is
    /// no. Nothing playful here: approvals are for trust. (2g turns this into the plan card.)
    private func approvalView(_ step: StepPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !step.preview.recipients.isEmpty {
                Text("To \(step.preview.recipients.joined(separator: ", "))")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The whole text, word for word. Only a very long message scrolls.
            let body = Text(approvalBody(step.preview))
                .font(.title3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if ApprovalLayout.scrolls(step.preview) {
                ScrollView { body }.frame(height: ApprovalLayout.maxBody)
            } else {
                body
            }
            HStack(spacing: 16) {
                Button { model.onAnswer(true) } label: {
                    // An amber fill always takes the dark label colour (brand rule).
                    Text(approveLabel(step))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NiloColor.onSignature)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(NiloColor.signature, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Return")
                Button("Cancel") { model.onAnswer(false) }
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHint("Escape")
            }
        }
    }

    private func approvalBody(_ preview: ToolPreview) -> String { ApprovalLayout.bodyText(preview) }

    private func approveLabel(_ step: StepPreview) -> String {
        switch step.toolName {
        case MessagesComposeTool.name: "Open in Messages"
        case WhatsAppComposeTool.name: "Open in WhatsApp"
        default: step.risk == .delete ? "Delete" : "Approve"
        }
    }

    /// Opens a System Settings pane by its id.
    private func turnOnPane(_ pane: String, hint: String) -> some View {
        Button("Turn on") {
            if let url = URL(string: "x-apple.systempreferences:\(pane)") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(NiloColor.signature)
        .fixedSize()
        .accessibilityHint(hint)
    }

    /// Opens the right page of Privacy & Security settings.
    private func turnOn(_ page: String, hint: String) -> some View {
        Button("Turn on") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(page)") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(NiloColor.signature)
        .fixedSize()
        .accessibilityHint(hint)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white.opacity(0.55))
    }

    /// Always laid out at full size. The growing shape reveals it.
    private func content(_ g: NotchGeometry) -> some View {
        let inset = 22 + g.shoulder(open: true)
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: g.notch.height)
            HStack(spacing: 14) {
                MarkView(state: mark.state, level: mark.level, height: 34, replay: mark.replay)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mark.state.label.uppercased())
                        .font(NiloFont.mono(11))
                        .tracking(1)
                        .foregroundStyle(NiloColor.needsYou)
                    ZStack(alignment: .leading) {
                        // The field stays focused underneath, so typing takes over at once.
                        field.opacity(showsVoice ? 0 : 1)
                        if showsVoice { voiceLine }
                    }
                }
            }
            .padding(.horizontal, inset)
            .frame(height: NotchGeometry.openSize.height - g.notch.height)

            if let reply = model.reply {
                // Lines up with the text above, under the ring's column.
                replyView(reply)
                    .padding(.leading, inset + 44 + 14)
                    .padding(.trailing, inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -8)
                    .frame(height: model.replyHeight, alignment: .top)
                    .transition(.opacity)
            }
        }
        .frame(width: NotchGeometry.openSize.width, height: NotchGeometry.openHeight(extra: model.replyHeight), alignment: .top)
        .onAppear { fieldFocused = true }
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
    private let mic = Microphone()
    private let transcriber = Transcriber()
    /// The real calendars and contacts. Asks for access the first time a tool needs it.
    private let calendar = EventKitCalendar()
    private let contacts = ContactsBook()
    /// Reads requests into a job's blanks: Apple's on-device model.
    private let reader = OnDeviceReader()
    /// The runner behind the Command-T test job, kept so Command-Shift-T can undo it.
    private var testRunner: JobRunner?
    /// A send or delete waiting for the person's answer.
    private var pendingApproval: CheckedContinuation<Bool, Never>?
    /// True while spoken words are being turned into text for this request.
    private var voiceOn = false
    /// The prototype's stand-in for real work: Thinking, then Done, then Idle.
    private var demo: Task<Void, Never>?
    /// While macOS shows its microphone question, app switches must not close the panel.
    private var askingPermission = false
    /// Hold to talk: when the shortcut went down, if that press opened the panel.
    private var heldSince: Double?
    private var shortcutDown = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Bumped on every open and close, so a late "order out" never hides a panel just reopened.
    private var generation = 0
    /// The screen the panel is on, for resizing when a reply appears.
    private var screen: NSScreen = .underPointer

    init(mark: MenuBarMark) {
        self.mark = mark
        model = NotchPanelModel(geometry: NotchGeometry(screen: .underPointer))
        let host = NSHostingView(rootView: NotchPanelView(model: model, mark: mark))
        host.sizingOptions = []
        panel.contentView = host

        mic.onLevel = { [weak mark] level in mark?.level = level }
        mic.onFinished = { [weak self] in self?.gotIt() }
        mic.sink = transcriber.sink
        transcriber.onText = { [weak self] settled, pending in
            guard let self, self.voiceOn else { return }
            self.model.voiceSettled = settled
            self.model.voicePending = pending
        }
        model.onType = { [weak self] in self?.typing() }
        model.onSubmit = { [weak self] text in self?.submit(text) }
        model.onAnswer = { [weak self] yes in self?.answer(yes) }
    }

    // MARK: The shortcut: tap to open and close, hold to talk

    func shortcutPressed() {
        guard !shortcutDown else { return }  // key repeat while held
        shortcutDown = true
        if model.expanded {
            close()
        } else {
            open()
            heldSince = ProcessInfo.processInfo.systemUptime
        }
    }

    func shortcutReleased() {
        shortcutDown = false
        defer { heldSince = nil }
        // Held long enough to be "hold to talk": letting go means "got it", no waiting for quiet.
        guard let since = heldSince, ProcessInfo.processInfo.systemUptime - since >= 0.4 else { return }
        gotIt()
    }

    // MARK: Listening

    /// Opening means listening: turn to the person and switch the mic on.
    private func startListening(generation gen: Int) {
        demo?.cancel()
        mark.set(.listening)
        askingPermission = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.mic.start()
            self.askingPermission = false
            // Closed, reopened or moved on while we waited: don't leave the mic on.
            guard self.generation == gen, self.model.expanded || self.model.visible, self.mark.state == .listening else {
                self.mic.stop()
                return
            }
            switch result {
            case .listening: break
            case .denied: self.setReply(.micOff)
            case .unavailable: self.setReply(.micMissing)
            }
        }
        startVoice(generation: gen)
    }

    /// Speech to text, alongside the mic. Buffers before it's ready are simply dropped.
    private func startVoice(generation gen: Int) {
        model.voiceSettled = ""
        model.voicePending = ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            let readiness = await self.transcriber.start { [weak self] progress in
                guard let self, progress == .downloading, self.model.reply == nil else { return }
                self.setReply(.voicePreparing)
            }
            if self.model.reply == .voicePreparing { self.setReply(nil) }
            // Closed, typed, or moved on while it got ready: no voice for this request.
            guard self.generation == gen, self.mark.state == .listening, self.model.draft.isEmpty else {
                await self.transcriber.cancel()
                return
            }
            switch readiness {
            case .ready, .downloading:
                self.voiceOn = true
            case .unsupported, .failed:
                if self.model.reply == nil { self.setReply(.voiceUnsupported) }
            }
        }
    }

    /// Stop turning speech into text. `keepWords` moves what was heard into the field.
    private func stopVoice(keepWords: Bool) {
        guard voiceOn else { return }
        voiceOn = false
        let heard = model.voiceText
        model.voiceSettled = ""
        model.voicePending = ""
        Task { @MainActor [weak self] in await self?.transcriber.cancel() }
        if keepWords, !heard.isEmpty {
            model.draft = heard + " " + model.draft
        }
    }

    /// The person is typing: Listening (facing them), mic off, and a new request clears the
    /// last reply.
    private func typing() {
        // Typing takes over from speaking: the words heard so far move into the field to edit.
        stopVoice(keepWords: true)
        if mic.isOn { mic.stop() }
        if mark.state != .listening {
            demo?.cancel()
            mark.set(.listening)
        }
        if pendingApproval != nil { answer(false) }
        switch model.reply {
        case .understood, .result, .approval: setReply(nil)
        default: break
        }
    }

    /// Return: send what was typed.
    private func submit(_ text: String) {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        model.draft = ""
        gotIt(request: request)
    }

    /// "Got it": the person has finished. The mic goes off, the ring blinks and turns back to
    /// the task. For now a short Thinking, then the reply and Done once, then Idle stand in for
    /// real work.
    private func gotIt(request: String? = nil) {
        guard mark.state == .listening else { return }
        // Spoken, not typed: the words come from the transcriber once it settles the last ones.
        let spoken = request == nil && voiceOn
        voiceOn = false
        mic.stop()
        mark.set(.thinking)
        demo?.cancel()
        demo = Task { @MainActor [weak self] in
            var heard = request
            if spoken, let self { heard = await self.transcriber.finish() }
            guard let self, !Task.isCancelled, self.mark.state == .thinking else { return }
            guard let heard, !heard.isEmpty else {
                self.model.voiceSettled = ""
                self.model.voicePending = ""
                if spoken { self.setReply(.notHeard) }
                self.mark.set(.idle)
                return
            }
            let understood = await self.understand(heard)
            guard !Task.isCancelled, self.mark.state == .thinking else { return }
            self.model.voiceSettled = ""
            self.model.voicePending = ""
            guard let understood else { return }  // a notice is already showing
            let (headline, details) = JobText.lines(understood)
            switch understood {
            case .addMeeting, .moveMeeting:
                self.finishJob(.understood(headline, details), done: true)
            case .question, .notAJob:
                self.finishJob(.understood(headline, []), done: false)
            }
        }
    }

    /// Reads the request with the on-device model, then works out the dates in code.
    /// Nil when the model can't be used or fails (a notice says why).
    private func understand(_ request: String) async -> Understood? {
        let availability = OnDeviceReader.availability
        guard availability == .ready else {
            finishJob(.modelOff(availability), done: false)
            return nil
        }
        do {
            let form = try await reader.read(request)
            return Understand.job(from: form, request: request, now: .now)
        } catch {
            finishJob(.result("That didn't work. Try again, or say it another way."), done: false)
            return nil
        }
    }

    /// Show or clear the reply. The window grows first and the shape follows, or the shape
    /// shrinks first and the window follows, so nothing is ever cut off.
    private func setReply(_ reply: NotchPanelModel.Reply?) {
        // Closed or closing: never resize a hidden window (it sends AppKit into a layout loop).
        guard model.visible, model.expanded else {
            model.reply = reply
            return
        }
        let old = model.replyHeight, new = reply?.height ?? 0
        if new > old {
            panel.setFrame(model.geometry.windowFrame(on: screen, extra: new), display: true)
        }
        withAnimation(model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15)) {
            model.reply = reply
        }
        if new < old {
            let gen = generation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.4))
                guard let self, self.generation == gen, self.model.visible, self.model.replyHeight == new else { return }
                self.panel.setFrame(self.model.geometry.windowFrame(on: self.screen, extra: new), display: true)
            }
        }
    }

    // MARK: Jobs

    /// Every tool Nilo can run. Sends and deletes ask the person in the panel.
    private func makeRunner() -> JobRunner {
        var registry = ToolRegistry()
        try? registry.register(FreeTimeTool(store: calendar))
        try? registry.register(FindEventsTool(store: calendar))
        try? registry.register(AddEventTool(store: calendar))
        try? registry.register(MoveEventTool(store: calendar))
        try? registry.register(FindPersonTool(store: contacts))
        try? registry.register(MessagesComposeTool(opener: AppMessageOpener()))
        try? registry.register(WhatsAppComposeTool(opener: AppMessageOpener()))
        let approver = PanelApprover { [weak self] step in await self?.ask(step) ?? false }
        return JobRunner(registry: registry, approver: approver, context: ToolContext(platform: .macOS))
    }

    // MARK: Approval

    /// Shows the exact preview and waits. The ring faces the person (Needs you: one hop, then still).
    private func ask(_ step: StepPreview) async -> Bool {
        guard model.visible else { return false }
        return await withCheckedContinuation { continuation in
            pendingApproval = continuation
            setReply(.approval(step))
            mark.set(.needsYou)
        }
    }

    /// The person's answer. Anything other than an explicit yes is a no.
    private func answer(_ yes: Bool) {
        guard let continuation = pendingApproval else { return }
        pendingApproval = nil
        mark.set(.working)
        continuation.resume(returning: yes)
    }

    /// Hidden test (Command-M, Command-Shift-M for WhatsApp): a message to yourself, from your
    /// own card in Contacts. It asks first, then opens the app with the text filled in.
    private func runMessageTest(whatsApp: Bool) {
        stopListening()
        model.draft = ""
        mark.set(.working)
        let runner = makeRunner()
        demo = Task { @MainActor [weak self] in
            guard let self else { return }
            let me: Person?
            do {
                me = try await self.contacts.me()
            } catch {
                return self.finishJob(self.reply(for: .failed(id: "me", (error as? ToolRunError) ?? .noAccess("contacts"))), done: false)
            }
            guard let me else {
                return self.finishJob(.result("Set your own card in Contacts first: Card, Make This My Card."), done: false)
            }
            guard let address = whatsApp ? me.phones.first : (me.phones.first ?? me.emails.first) else {
                return self.finishJob(.result("Your card in Contacts has no phone number."), done: false)
            }
            let who = Recipient(name: me.name, address: address)
            let text = "Hello from Nilo."
            let call = whatsApp
                ? Self.call("send", WhatsAppComposeTool.name, WhatsAppComposeTool.Input(recipient: who, text: text))
                : Self.call("send", MessagesComposeTool.name, MessagesComposeTool.Input(recipients: [who], text: text))
            let result = await runner.run([call])
            guard !Task.isCancelled else { return }
            if result.outcome == .completed {
                self.finishJob(.result(whatsApp ? "WhatsApp is open. Tap Send there." : "Messages is open. Tap Send there."), done: true)
            } else {
                self.finishJob(self.reply(for: result.outcome), done: false)
            }
        }
    }

    /// Hidden test (Command-T): find the first free 30 minutes tomorrow and add "Nilo test"
    /// there, in the Nilo Test calendar.
    private func runCalendarTest() {
        stopListening()
        model.draft = ""
        mark.set(.working)
        let runner = makeRunner()
        testRunner = runner
        demo = Task { @MainActor [weak self] in
            let cal = Calendar.current
            let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
            let dayAfter = cal.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
            let find = await runner.run([Self.call("free", FreeTimeTool.name, FreeTimeTool.Input(from: tomorrow, to: dayAfter, minutes: 30))])
            guard let self, !Task.isCancelled else { return }
            guard find.outcome == .completed,
                  let data = find.outputs["free"],
                  let free = try? ToolJSON.decoder.decode(FreeTimeTool.Output.self, from: data) else {
                return self.finishJob(self.reply(for: find.outcome), done: false)
            }
            guard let slot = free.slots.first else {
                return self.finishJob(.result("No free 30 minutes tomorrow."), done: false)
            }
            let end = slot.start.addingTimeInterval(30 * 60)
            let add = await runner.run([Self.call("add", AddEventTool.name, EventDraft(title: "Nilo test", start: slot.start, end: end))])
            guard !Task.isCancelled else { return }
            guard add.outcome == .completed else { return self.finishJob(self.reply(for: add.outcome), done: false) }
            self.finishJob(.result("Added Nilo test, \(WhenText.range(slot.start, end))."), done: true)
        }
    }

    /// Hidden test (Command-Shift-T): undo the test job.
    private func undoCalendarTest() {
        stopListening()
        guard let runner = testRunner else { return finishJob(.result("Nothing to undo."), done: false) }
        testRunner = nil
        mark.set(.working)
        demo = Task { @MainActor [weak self] in
            let failures = await runner.undoAll()
            guard let self, !Task.isCancelled else { return }
            self.finishJob(.result(failures.isEmpty ? "Removed Nilo test." : "Couldn't undo that."), done: failures.isEmpty)
        }
    }

    /// Show what happened. Done plays only when the job finished.
    private func finishJob(_ reply: NotchPanelModel.Reply, done: Bool) {
        setReply(reply)
        mark.set(done ? .done : .idle)
        guard done else { return }
        demo = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, !Task.isCancelled, self.mark.state == .done else { return }
            self.mark.set(.idle)
        }
    }

    private func reply(for outcome: JobResult.Outcome) -> NotchPanelModel.Reply {
        let error: ToolRunError
        switch outcome {
        case .completed: return .result("Done.")
        case .declined: return .result("Stopped. Nothing was sent.")
        case .refused(let e), .failed(_, let e): error = e
        }
        switch error {
        case .noAccess("calendar"): return .calendarOff
        case .noAccess: return .contactsOff
        case .notAllowed(_, let reason): return .result(reason)
        case .failed(_, let message): return .result("That didn't work. \(message)")
        default: return .result("That didn't work.")
        }
    }

    private static func call<T: Encodable>(_ id: String, _ tool: String, _ input: T) -> ToolCall {
        ToolCall(id: id, toolName: tool, argumentsJSON: (try? ToolJSON.encoder.encode(input)) ?? Data())
    }

    private func stopListening() {
        demo?.cancel()
        demo = nil
        stopVoice(keepWords: false)
        mic.stop()
    }

    func toggle() {
        model.expanded ? close() : open()
    }

    func open() {
        generation += 1
        let gen = generation
        let screen = NSScreen.underPointer
        self.screen = screen
        model.geometry = NotchGeometry(screen: screen)
        model.reply = nil
        model.draft = ""
        model.voiceSettled = ""
        model.voicePending = ""
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.expanded = false
        model.visible = true
        panel.setFrame(model.geometry.windowFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        panel.makeKey()
        startWatching()
        startListening(generation: gen)

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
        answer(false)  // closing is never a yes
        stopWatching()
        stopListening()
        if mark.state != .idle { mark.set(.idle) }
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
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated {
                self?.handleKey(code: code, chars: chars, shift: shift, command: command) ?? false
            }
            return handled ? nil : event
        }) { monitors.append(m) }

        // Switching apps, Spaces or screens closes it too.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A permission question from macOS counts as switching apps. Don't close for
                    // it, or in the middle of a job.
                    guard let self, !self.askingPermission, self.mark.state != .working else { return }
                    self.close()
                }
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

    /// Esc closes (or says no to a waiting approval; Return says yes). Every other key goes to the
    /// text field, except the hidden test keys: Tab next state, Shift-Tab previous, Command-R
    /// play again, Command-T calendar test job, Command-Shift-T undo it, Command-M message
    /// yourself in Messages, Command-Shift-M in WhatsApp.
    private func handleKey(code: UInt16, chars: String?, shift: Bool, command: Bool) -> Bool {
        switch code {
        case 53:                                  // Esc: no to a waiting approval, else close
            if pendingApproval != nil { answer(false) } else { close() }
        case 36, 76:                              // Return: yes to a waiting approval
            guard pendingApproval != nil else { return false }
            answer(true)
        case 48:                                  // Tab
            stopListening()
            mark.step(shift ? -1 : 1)
        default:
            guard command else { return false }
            switch chars {
            case "r": mark.replayNow()
            case "t": shift ? undoCalendarTest() : runCalendarTest()
            case "m": runMessageTest(whatsApp: shift)
            default: return false
            }
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

/// Joins two runs of words with one space where needed.
func joinWords(_ a: String, _ b: String) -> String {
    if a.isEmpty { return b.trimmingCharacters(in: .whitespaces) }
    if b.isEmpty { return a.trimmingCharacters(in: .whitespaces) }
    let gap = a.hasSuffix(" ") || b.hasPrefix(" ") ? "" : " "
    return (a + gap + b).trimmingCharacters(in: .whitespaces)
}

/// Asks the person in the panel.
struct PanelApprover: Approver {
    let ask: @MainActor @Sendable (StepPreview) async -> Bool
    func approve(_ step: StepPreview) async -> Bool { await ask(step) }
}

/// Sizes the approval area to fit everything it must show, measured up front so the window
/// never has to ask SwiftUI (that path leads to AppKit layout loops).
enum ApprovalLayout {
    /// The text column under the request, at its narrowest (on a notch).
    static let width: CGFloat = NotchGeometry.openSize.width - 2 * 34 - 44 - 14
    /// Longer messages scroll inside this height.
    static let maxBody: CGFloat = 160

    static func height(_ preview: ToolPreview) -> CGFloat {
        let to = preview.recipients.isEmpty ? 0 : measure("To " + preview.recipients.joined(separator: ", "), .body) + 6
        let body = min(measure(bodyText(preview), .title3), maxBody)
        let buttons: CGFloat = 28
        return to + body + 6 + buttons + 14
    }

    static func scrolls(_ preview: ToolPreview) -> Bool {
        measure(bodyText(preview), .title3) > maxBody
    }

    static func bodyText(_ preview: ToolPreview) -> String {
        if let text = preview.text { return text }
        if !preview.items.isEmpty { return preview.items.joined(separator: "\n") }
        return preview.title
    }

    /// An understood job: the headline, then each detail line.
    static func height(headline: String, details: [String]) -> CGFloat {
        let lines = measure(headline, .title3) + details.reduce(0) { $0 + measure($1, .body) + 2 }
        return max(NotchGeometry.replyHeight, lines + 12)
    }

    static func measure(_ text: String, _ style: NSFont.TextStyle) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: style)
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height) + 2
    }
}
