import Foundation

// Understanding a request, in two halves:
// 1. A reader (Apple's on-device model now, Claude later) fills in a fixed form: which job,
//    who, the "when" in the person's own words, and so on. It can't invent a job or an action.
// 2. Plain code turns the form into a job with real dates. No model does date maths.
// If something is missing or unclear, Nilo asks one plain question instead of guessing.

// MARK: - The form a reader fills in

public struct RequestForm: Codable, Sendable, Equatable {
    public enum Job: String, Codable, Sendable { case addMeeting, moveMeeting, other }

    public var job: Job
    /// The new meeting's title, if said.
    public var title: String
    public var people: [String]
    /// When the new meeting is, or when to move it to, in the person's own words.
    public var when: String
    /// For a move: the words that identify the existing meeting ("my 3pm", "the design review").
    public var meeting: String
    /// Length in minutes if said, else 0.
    public var minutes: Int
    /// The reason to give people, word for word.
    public var reason: String
    public var tellPeople: Bool

    public init(job: Job, title: String = "", people: [String] = [], when: String = "", meeting: String = "",
                minutes: Int = 0, reason: String = "", tellPeople: Bool = false) {
        self.job = job
        self.title = title
        self.people = people
        self.when = when
        self.meeting = meeting
        self.minutes = minutes
        self.reason = reason
        self.tellPeople = tellPeople
    }
}

/// Reads a request into a form. The UI never knows which reader answered.
public protocol RequestReader: Sendable {
    func read(_ request: String) async throws -> RequestForm
}

// MARK: - Jobs with real dates

public struct AddMeetingJob: Sendable, Equatable {
    public var title: String
    public var people: [String]
    public var start: Date
    public var end: Date
    public var tellPeople: Bool
}

public struct MoveMeetingJob: Sendable, Equatable {
    /// The words that identify the meeting. Finding the event itself is part of job 2.
    public var meeting: String
    /// When the meeting is now, if the words say (e.g. "my 3pm" → today 15:00).
    public var currently: Date?
    public var newStart: Date
    /// Only set when a new length was said; otherwise the meeting keeps its length.
    public var newMinutes: Int?
    public var reason: String
    public var tellPeople: Bool
}

public enum Understood: Sendable, Equatable {
    case addMeeting(AddMeetingJob)
    case moveMeeting(MoveMeetingJob)
    /// Something is missing: one plain question.
    case question(String)
    /// Not one of the jobs Nilo knows.
    case notAJob
}

public enum Understand {
    public static let defaultMinutes = 30

    /// Turns a filled-in form into a job with real dates, counted from `now`. With the original
    /// `request`, plain code double-checks the model: "tell" needs a telling word in the request,
    /// and a time the model left out of "when" is read from the request itself.
    public static func job(from form: RequestForm, request: String? = nil, now: Date, calendar: Calendar = .current) -> Understood {
        var form = form
        if let request {
            if form.job == .moveMeeting, form.meeting.trimmed.isEmpty {
                form.meeting = meetingWords(request) ?? ""
            }
            form.tellPeople = form.tellPeople && asksToTell(request)
            form.when = fullerWhen(form, request: request, now: now, calendar: calendar)
        }
        switch form.job {
        case .other:
            return .notAJob
        case .addMeeting:
            guard !form.when.trimmed.isEmpty else { return .question("When should it be?") }
            guard let when = WhenReader.read(form.when, now: now, calendar: calendar) else {
                return .question("Which day and time? Try \u{201C}Thursday at 3\u{201D}.")
            }
            guard let start = when.date else { return .question("What time?") }
            let minutes = form.minutes > 0 ? form.minutes : defaultMinutes
            let people = form.people.map(\.trimmed).filter { !$0.isEmpty }
            return .addMeeting(AddMeetingJob(
                title: title(form.title, people: people),
                people: people,
                start: start,
                end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                tellPeople: form.tellPeople && !people.isEmpty
            ))
        case .moveMeeting:
            guard !form.meeting.trimmed.isEmpty else { return .question("Which meeting should move?") }
            guard !form.when.trimmed.isEmpty else { return .question("When should it move to?") }
            guard let to = WhenReader.read(form.when, now: now, calendar: calendar), let newStart = to.date else {
                return .question("When should it move to? Try \u{201C}Friday at 10\u{201D}.")
            }
            // "my 3pm" says when the meeting is now: any time today, even if it has started.
            let currently = WhenReader.read(form.meeting, now: now, calendar: calendar, allowPast: true)?.date
            return .moveMeeting(MoveMeetingJob(
                meeting: form.meeting.trimmed,
                currently: currently,
                newStart: newStart,
                newMinutes: form.minutes > 0 ? form.minutes : nil,
                reason: form.reason.trimmed,
                tellPeople: form.tellPeople
            ))
        }
    }

    /// "Move the standup to 11:30" → "the standup". A fallback when the model leaves it empty.
    static func meetingWords(_ request: String) -> String? {
        guard let m = request.firstMatch(of: /(?i)\b(?:move|push|reschedule|shift|bump|change)\s+(.+?)\s+(?:to|till|until)\b/) else {
            return nil
        }
        let words = String(m.1).trimmed
        return words.isEmpty ? nil : words
    }

    /// Words that ask Nilo to tell people. Without one, the model's "tell" doesn't count.
    static func asksToTell(_ request: String) -> Bool {
        let s = " " + request.lowercased() + " "
        let cues = [" tell ", " let ", " know", " message", " text ", " text,", " whatsapp", " notify", " inform", " heads-up", " heads up", " send them", " send her", " send him", " email "]
        return cues.contains { s.contains($0) }
    }

    /// When the model's "when" has no time but the request does, use the request's words.
    /// For a move, the words naming the meeting ("my 3pm") are taken out first.
    static func fullerWhen(_ form: RequestForm, request: String, now: Date, calendar: Calendar) -> String {
        guard form.job != .other else { return form.when }
        if !form.when.trimmed.isEmpty, WhenReader.read(form.when, now: now, calendar: calendar)?.date != nil {
            return form.when
        }
        var rest = request
        if !form.meeting.trimmed.isEmpty {
            rest = rest.replacingOccurrences(of: form.meeting, with: " ", options: .caseInsensitive)
        }
        guard WhenReader.read(rest, now: now, calendar: calendar)?.date != nil else { return form.when }
        return rest
    }

    /// The title said, or "Meeting with Maria". A generic title the model made up counts as none.
    static func title(_ said: String, people: [String]) -> String {
        let t = said.trimmed
        let generic = t.isEmpty || t.lowercased() == "meeting" || t.lowercased().hasPrefix("meeting with")
        if !generic { return t }
        return people.isEmpty ? "Meeting" : "Meeting with \(ListText.join(people))"
    }
}

// MARK: - Reading "when"

/// Reads a day and time in plain English ("Thursday at 3", "tomorrow 10:30am", "27 Nov at noon").
/// Deterministic and testable; no model involved. Returns nil when it can't tell.
public enum WhenReader {
    public struct When: Equatable, Sendable {
        public var day: Date
        /// Nil when no time was said.
        public var date: Date?
    }

    public static func read(_ text: String, now: Date, calendar: Calendar = .current, allowPast: Bool = false) -> When? {
        var s = " " + text.lowercased().replacingOccurrences(of: ",", with: " ") + " "
        let today = calendar.startOfDay(for: now)

        // The day.
        var day: Date?
        var sameWeekday = false
        if let (d, rest) = explicitDate(s, today: today, calendar: calendar) {
            day = d; s = rest
        } else if s.contains(" day after tomorrow ") {
            day = calendar.date(byAdding: .day, value: 2, to: today); s = s.replacingOccurrences(of: " day after tomorrow ", with: " ")
        } else if s.contains(" tomorrow ") {
            day = calendar.date(byAdding: .day, value: 1, to: today); s = s.replacingOccurrences(of: " tomorrow ", with: " ")
        } else if s.contains(" today ") || s.contains(" tonight ") {
            day = today
        } else if let (n, rest) = inDays(s) {
            day = calendar.date(byAdding: .day, value: n, to: today); s = rest
        } else if let (weekday, isNext, rest) = weekday(s) {
            let current = calendar.component(.weekday, from: today)
            var ahead = (weekday - current + 7) % 7
            if ahead == 0, isNext { ahead = 7 } // "next Wednesday" said on a Wednesday
            sameWeekday = ahead == 0
            day = calendar.date(byAdding: .day, value: ahead, to: today); s = rest
        }

        // The time.
        let time = self.time(s)
        guard day != nil || time != nil else { return nil }

        guard let (hour, minute) = time else {
            return day.map { When(day: $0, date: nil) }
        }
        let baseDay = day ?? today
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay) else { return nil }
        // Only a time: today if it's still ahead, else tomorrow.
        if day == nil, date <= now, !allowPast, let next = calendar.date(byAdding: .day, value: 1, to: date) {
            date = next
        }
        // Today's weekday: today if the time is still ahead, else next week.
        if sameWeekday, date <= now, !allowPast, let next = calendar.date(byAdding: .day, value: 7, to: date) {
            date = next
        }
        return When(day: calendar.startOfDay(for: date), date: date)
    }

    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("sun", 1), ("monday", 2), ("mon", 2), ("tuesday", 3), ("tues", 3), ("tue", 3),
        ("wednesday", 4), ("wed", 4), ("thursday", 5), ("thurs", 5), ("thu", 5), ("friday", 6), ("fri", 6),
        ("saturday", 7), ("sat", 7),
    ]

    private static let months: [(String, Int)] = [
        ("january", 1), ("jan", 1), ("february", 2), ("feb", 2), ("march", 3), ("mar", 3), ("april", 4), ("apr", 4),
        ("may", 5), ("june", 6), ("jun", 6), ("july", 7), ("jul", 7), ("august", 8), ("aug", 8),
        ("september", 9), ("sept", 9), ("sep", 9), ("october", 10), ("oct", 10), ("november", 11), ("nov", 11),
        ("december", 12), ("dec", 12),
    ]

    private static func weekday(_ s: String) -> (Int, Bool, String)? {
        for (name, number) in weekdays {
            for form in [" next \(name) ", " this \(name) ", " on \(name) ", " \(name) "] where s.contains(form) {
                return (number, form.hasPrefix(" next"), s.replacingOccurrences(of: form, with: " "))
            }
        }
        return nil
    }

    private static func inDays(_ s: String) -> (Int, String)? {
        guard let m = s.firstMatch(of: /\sin (\d{1,2}) days?\s/), let n = Int(m.1) else { return nil }
        return (n, s.replacingCharacters(in: m.range, with: " "))
    }

    /// "27 november", "27th nov", "november 27", "nov 27th". This year, or next if already past.
    private static func explicitDate(_ s: String, today: Date, calendar: Calendar) -> (Date, String)? {
        for (name, month) in months {
            let patterns = [
                try! Regex("\\s(\\d{1,2})(?:st|nd|rd|th)?(?: of)? \(name)\\b"),
                try! Regex("\\s\(name) (\\d{1,2})(?:st|nd|rd|th)?\\b"),
            ]
            for pattern in patterns {
                guard let m = s.firstMatch(of: pattern),
                      let dayText = m.output[1].substring, let dayNumber = Int(dayText) else { continue }
                let year = calendar.component(.year, from: today)
                guard var date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) else { continue }
                if date < today, let next = calendar.date(from: DateComponents(year: year + 1, month: month, day: dayNumber)) {
                    date = next
                }
                return (date, s.replacingCharacters(in: m.range, with: " "))
            }
        }
        return nil
    }

    /// "3", "3pm", "3:30", "15:00", "10.30am", "noon", "midnight". A bare 1 to 7 means afternoon.
    private static func time(_ s: String) -> (Int, Int)? {
        if s.contains("noon") { return (12, 0) }
        if s.contains("midnight") { return (0, 0) }
        guard let m = s.firstMatch(of: /(?:^|\s|at)(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?=\s|$)/),
              var hour = Int(m.1) else { return nil }
        let minute = m.2.flatMap { Int($0) } ?? 0
        guard hour <= 23, minute <= 59 else { return nil }
        let marker = m.3.map { String($0).replacingOccurrences(of: ".", with: "") }
        switch marker {
        case "pm": if hour < 12 { hour += 12 }
        case "am": if hour == 12 { hour = 0 }
        default: if (1...7).contains(hour) { hour += 12 } // "at 3" means 3 pm at work
        }
        return (hour, minute)
    }
}

// MARK: - Words

public enum ListText {
    /// "Maria", "Maria and Joe", "Maria, Joe and Ana".
    public static func join(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

public enum JobText {
    /// The headline and the detail lines the panel shows for an understood job.
    public static func lines(_ understood: Understood) -> (headline: String, details: [String]) {
        switch understood {
        case .addMeeting(let job):
            var details = [WhenText.range(job.start, job.end)]
            if job.tellPeople { details.append("Tell \(ListText.join(job.people))") }
            // "Add a meeting with Maria" for the plain title, "Add Design review" for a named one.
            let headline = job.title.hasPrefix("Meeting")
                ? "Add a m" + job.title.dropFirst()
                : "Add \(job.title)"
            return (headline, details)
        case .moveMeeting(let job):
            let what = job.meeting
            var details = ["To \(job.newStart.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))"]
            if job.tellPeople {
                details.append(job.reason.isEmpty ? "Tell them" : "Tell them: \u{201C}\(job.reason)\u{201D}")
            }
            return ("Move \(what)", details)
        case .question(let q):
            return (q, [])
        case .notAJob:
            return ("Nilo can add or move meetings for now.", [])
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
