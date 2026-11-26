import Foundation
import Testing
@testable import NiloCore

// A trial of the real on-device model on everyday requests. It needs Apple Intelligence on
// the machine, so it only runs when asked:
//
//     NILO_MODEL_TRIAL=1 swift test --filter ModelTrial
//
// It prints a score and every miss. Use it whenever the reader's instructions change.

struct TrialCase: Sendable {
    var request: String
    var job: RequestForm.Job
    var people: Set<String> = []
    /// Expected start (add) or new start (move), counted from Wednesday 3 March 2027, 11:00 UTC.
    var start: Date?
    var tell = false
    /// For a move: words the meeting description must contain.
    var meeting: String?
    /// Words the reason must contain.
    var reason: String?
}

let trialCases: [TrialCase] = [
    .init(request: "Add a meeting with Maria on Thursday at 3 and let her know", job: .addMeeting, people: ["maria"], start: on(4, 15), tell: true),
    .init(request: "Lunch with Joe and Ana next Tue 1pm", job: .addMeeting, people: ["joe", "ana"], start: on(9, 13)),
    .init(request: "Set up a design review with Nikos tomorrow at 10am for an hour", job: .addMeeting, people: ["nikos"], start: on(4, 10)),
    .init(request: "Book a call with Sarah Friday 4:30pm and text her the details", job: .addMeeting, people: ["sarah"], start: on(5, 16, 30), tell: true),
    .init(request: "Coffee with Tom tomorrow at 9", job: .addMeeting, people: ["tom"], start: on(4, 9)),
    .init(request: "Schedule a 1:1 with Elena on Monday at 11 and let her know", job: .addMeeting, people: ["elena"], start: on(8, 11), tell: true),
    .init(request: "Put a meeting with the Acme team in my calendar on 27 November at 2pm", job: .addMeeting, start: on(27, 14, month: 11)),
    .init(request: "Meeting with Kostas and Dimitra Friday at noon, tell them", job: .addMeeting, people: ["kostas", "dimitra"], start: on(5, 12), tell: true),
    .init(request: "Add dentist appointment Thursday 8:15am", job: .addMeeting, start: on(4, 8, 15)),
    .init(request: "Plan a catch up with Leo the day after tomorrow at 5pm", job: .addMeeting, people: ["leo"], start: on(5, 17)),
    .init(request: "Move my 3pm to Friday at 10 and tell them I'm stuck on a call", job: .moveMeeting, start: on(5, 10), tell: true, meeting: "3", reason: "stuck on a call"),
    .init(request: "Push the design review to tomorrow at 4", job: .moveMeeting, start: on(4, 16), meeting: "design review"),
    .init(request: "Reschedule my meeting with Maria to Monday 9am and let her know", job: .moveMeeting, people: ["maria"], start: on(8, 9), tell: true, meeting: "maria"),
    .init(request: "Can you move the standup to 11:30 tomorrow, I have a doctor's appointment, tell the team", job: .moveMeeting, start: on(4, 11, 30), tell: true, meeting: "standup", reason: "doctor"),
    .init(request: "Shift my 2pm call to Thursday at 3", job: .moveMeeting, start: on(4, 15), meeting: "2"),
    .init(request: "Move lunch with Joe to next Wednesday at 1pm", job: .moveMeeting, people: ["joe"], start: on(10, 13), meeting: "lunch"),
    .init(request: "What's the weather tomorrow?", job: .other),
    .init(request: "Send Maria the slides", job: .other),
    .init(request: "Summarise my unread email", job: .other),
    .init(request: "Remind me to call mum", job: .other),
]

@Suite("ModelTrial", .enabled(if: ProcessInfo.processInfo.environment["NILO_MODEL_TRIAL"] != nil))
struct ModelTrialTests {
    @Test func everydayRequests() async throws {
        #if canImport(FoundationModels)
        guard OnDeviceReader.availability == .ready else {
            Issue.record("The on-device model isn't ready: \(OnDeviceReader.availability)")
            return
        }
        let reader = OnDeviceReader()
        var right = 0
        var misses: [String] = []
        let started = Date()
        for c in trialCases {
            let form: RequestForm
            do {
                form = try await reader.read(c.request)
            } catch {
                misses.append("\(c.request)\n    error: \(error)")
                continue
            }
            var problems: [String] = []
            if form.job != c.job { problems.append("job \(form.job), expected \(c.job)") }
            if c.job != .other {
                let people = Set(form.people.map { $0.lowercased().split(separator: " ").first.map(String.init) ?? "" })
                if !c.people.isSubset(of: people) { problems.append("people \(form.people)") }
                
                let understood = Understand.job(from: form, request: c.request, now: wednesday11, calendar: utc)
                let start: Date? = switch understood {
                case .addMeeting(let j): j.start
                case .moveMeeting(let j): j.newStart
                default: nil
                }
                let tell: Bool = switch understood {
                case .addMeeting(let j): j.tellPeople
                case .moveMeeting(let j): j.tellPeople
                default: false
                }
                if tell != c.tell { problems.append("tell \(tell) (model said \(form.tellPeople))") }
                if start != c.start { problems.append("when \u{201C}\(form.when)\u{201D} → \(start.map { "\($0)" } ?? "none")") }
                let meeting: String = if case .moveMeeting(let j) = understood { j.meeting } else { "" }
                if let m = c.meeting, !meeting.lowercased().contains(m) { problems.append("meeting \u{201C}\(meeting)\u{201D}") }
                if let r = c.reason, !form.reason.lowercased().contains(r) { problems.append("reason \u{201C}\(form.reason)\u{201D}") }
            }
            if problems.isEmpty { right += 1 } else { misses.append("\(c.request)\n    " + problems.joined(separator: "; ")) }
        }
        let seconds = Date().timeIntervalSince(started) / Double(trialCases.count)
        print("MODEL TRIAL: \(right) of \(trialCases.count) right, \(String(format: "%.1f", seconds)) s each")
        for m in misses { print("MISS: \(m)") }
        #endif
    }
}
