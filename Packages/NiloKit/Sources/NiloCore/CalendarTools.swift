import Foundation

// Calendar tools: free time, find events, add an event, move an event.
//
// Until TestFlight, Nilo writes only to the "Nilo Test" calendar (see CLAUDE.md). It may read
// every calendar. Adding always goes to Nilo Test; moving refuses any event outside it.

// MARK: - Models

public struct CalendarEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// False for events marked "free", which don't block time.
    public var isBusy: Bool
    public var calendarID: String
    public var calendarTitle: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isBusy: Bool = true,
                calendarID: String, calendarTitle: String) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
    }
}

public struct EventDraft: Codable, Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String?
    public var location: String?

    public init(title: String, start: Date, end: Date, notes: String? = nil, location: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
    }
}

public struct TimeSlot: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// The part of the day Nilo offers for meetings. A setting later.
public struct WorkingHours: Sendable, Equatable {
    public var startHour: Int
    public var endHour: Int
    public init(startHour: Int = 9, endHour: Int = 18) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

public enum TestCalendar {
    /// The only calendar Nilo writes to until TestFlight.
    public static let title = "Nilo Test"
}

/// Where calendar data comes from. EventKit in the apps, a pretend calendar in tests.
public protocol CalendarStore: Sendable {
    /// Events on every calendar that overlap the range.
    func events(from: Date, to: Date) async throws -> [CalendarEvent]
    func event(id: String) async throws -> CalendarEvent?
    /// The Nilo Test calendar, created the first time it's needed.
    func testCalendarID() async throws -> String
    func add(_ draft: EventDraft, to calendarID: String) async throws -> CalendarEvent
    func move(eventID: String, start: Date, end: Date) async throws -> CalendarEvent
    func remove(eventID: String) async throws
}

// MARK: - Free time

public enum FreeTime {
    /// Open stretches of at least `minimum` seconds inside working hours, between `from` and `to`.
    /// Busy timed events block time. All-day events (holidays, birthdays) and events marked free
    /// don't.
    public static func slots(
        from: Date, to: Date, events: [CalendarEvent], minimum: TimeInterval,
        hours: WorkingHours = WorkingHours(), calendar: Calendar = .current
    ) -> [TimeSlot] {
        let busy = events
            .filter { $0.isBusy && !$0.isAllDay }
            .map { (start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }
        var result: [TimeSlot] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            guard let dayStart = calendar.date(bySettingHour: hours.startHour, minute: 0, second: 0, of: day),
                  let dayEnd = calendar.date(bySettingHour: hours.endHour, minute: 0, second: 0, of: day),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            var cursor = max(dayStart, from)
            let end = min(dayEnd, to)
            if cursor < end {
                for block in busy where block.end > cursor && block.start < end {
                    if block.start > cursor, block.start.timeIntervalSince(cursor) >= minimum {
                        result.append(TimeSlot(start: cursor, end: block.start))
                    }
                    cursor = max(cursor, block.end)
                    if cursor >= end { break }
                }
                if end.timeIntervalSince(cursor) >= minimum {
                    result.append(TimeSlot(start: cursor, end: end))
                }
            }
            day = next
        }
        return result
    }
}

// MARK: - Words for previews

public enum WhenText {
    /// "Thursday 27 November, 10:00 to 10:30", in the person's own date and time style.
    public static func range(_ start: Date, _ end: Date) -> String {
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(day), \(from) to \(to)"
    }
}

// MARK: - Tools

public struct FreeTimeTool: AssistantTool {
    public struct Input: Codable, Sendable {
        public var from: Date
        public var to: Date
        public var minutes: Int
        public init(from: Date, to: Date, minutes: Int) {
            self.from = from
            self.to = to
            self.minutes = minutes
        }
    }

    public struct Output: Codable, Sendable {
        public var slots: [TimeSlot]
    }

    public static let name = "calendar.free_time"
    public static let summary = "Finds open time of at least the given minutes between two dates, across all calendars, within working hours."
    public static let risk = Risk.read
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let store: any CalendarStore
    private let hours: WorkingHours

    public init(store: any CalendarStore, hours: WorkingHours = WorkingHours()) {
        self.store = store
        self.hours = hours
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        guard input.minutes > 0, input.to > input.from else { throw ToolRunError.badArguments(Self.name) }
        return ToolPreview(title: "Find \(input.minutes) free minutes, \(WhenText.range(input.from, input.to))")
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Output {
        let events = try await store.events(from: input.from, to: input.to)
        let slots = FreeTime.slots(from: input.from, to: input.to, events: events,
                                   minimum: TimeInterval(input.minutes * 60), hours: hours)
        return Output(slots: slots)
    }
}

public struct FindEventsTool: AssistantTool {
    public struct Input: Codable, Sendable {
        public var from: Date
        public var to: Date
        /// Part of the title to match, any case. Nil finds every event in the range.
        public var title: String?
        public init(from: Date, to: Date, title: String? = nil) {
            self.from = from
            self.to = to
            self.title = title
        }
    }

    public struct Output: Codable, Sendable {
        public var events: [CalendarEvent]
    }

    public static let name = "calendar.find_events"
    public static let summary = "Finds events between two dates, optionally by part of their title."
    public static let risk = Risk.read
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let store: any CalendarStore

    public init(store: any CalendarStore) {
        self.store = store
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        guard input.to > input.from else { throw ToolRunError.badArguments(Self.name) }
        let what = input.title.map { "\u{201C}\($0)\u{201D}" } ?? "events"
        return ToolPreview(title: "Look for \(what), \(WhenText.range(input.from, input.to))")
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Output {
        var events = try await store.events(from: input.from, to: input.to)
        if let title = input.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            events = events.filter { $0.title.localizedCaseInsensitiveContains(title) }
        }
        return Output(events: events.sorted { $0.start < $1.start })
    }
}

public struct AddEventTool: ReversibleTool {
    public typealias Input = EventDraft

    public struct Output: Codable, Sendable {
        public var event: CalendarEvent
    }

    public static let name = "calendar.add_event"
    public static let summary = "Adds an event to the Nilo Test calendar."
    public static let risk = Risk.change
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let store: any CalendarStore

    public init(store: any CalendarStore) {
        self.store = store
    }

    public func preview(_ input: EventDraft, in context: ToolContext) async throws -> ToolPreview {
        guard !input.title.trimmingCharacters(in: .whitespaces).isEmpty, input.end > input.start else {
            throw ToolRunError.badArguments(Self.name)
        }
        return ToolPreview(title: "Add \(input.title), \(WhenText.range(input.start, input.end))",
                           details: ["In the \(TestCalendar.title) calendar"])
    }

    public func run(_ input: EventDraft, in context: ToolContext) async throws -> Output {
        let calendarID = try await store.testCalendarID()
        return Output(event: try await store.add(input, to: calendarID))
    }

    public func undo(_ input: EventDraft, output: Output, in context: ToolContext) async throws {
        try await store.remove(eventID: output.event.id)
    }
}

public struct MoveEventTool: ReversibleTool {
    public struct Input: Codable, Sendable {
        public var eventID: String
        public var start: Date
        public var end: Date
        public init(eventID: String, start: Date, end: Date) {
            self.eventID = eventID
            self.start = start
            self.end = end
        }
    }

    public struct Output: Codable, Sendable {
        public var event: CalendarEvent
        public var previousStart: Date
        public var previousEnd: Date
    }

    public static let name = "calendar.move_event"
    public static let summary = "Moves an event in the Nilo Test calendar to a new time."
    public static let risk = Risk.change
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let store: any CalendarStore

    public init(store: any CalendarStore) {
        self.store = store
    }

    /// Checked before anything runs, so a forbidden move refuses the whole job.
    private func movable(_ input: Input) async throws -> CalendarEvent {
        guard input.end > input.start else { throw ToolRunError.badArguments(Self.name) }
        guard let event = try await store.event(id: input.eventID) else {
            throw ToolRunError.failed(Self.name, message: "That event no longer exists.")
        }
        guard event.calendarID == (try await store.testCalendarID()) else {
            throw ToolRunError.notAllowed(Self.name, reason: "Nilo only moves events in the \(TestCalendar.title) calendar for now.")
        }
        return event
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        let event = try await movable(input)
        return ToolPreview(title: "Move \(event.title) to \(WhenText.range(input.start, input.end))",
                           details: ["Was \(WhenText.range(event.start, event.end))"])
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Output {
        let event = try await movable(input)
        let moved = try await store.move(eventID: event.id, start: input.start, end: input.end)
        return Output(event: moved, previousStart: event.start, previousEnd: event.end)
    }

    public func undo(_ input: Input, output: Output, in context: ToolContext) async throws {
        _ = try await store.move(eventID: output.event.id, start: output.previousStart, end: output.previousEnd)
    }
}
