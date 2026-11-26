import Foundation
import Testing
@testable import NiloCore

// MARK: - Pretend calendar and contacts

actor PretendCalendar: CalendarStore {
    static let testID = "nilo-test"
    private(set) var events: [CalendarEvent]
    private var next = 0

    init(_ events: [CalendarEvent] = []) { self.events = events }

    func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        events.filter { $0.end > from && $0.start < to }
    }
    func event(id: String) async throws -> CalendarEvent? { events.first { $0.id == id } }
    func testCalendarID() async throws -> String { Self.testID }
    func add(_ draft: EventDraft, to calendarID: String) async throws -> CalendarEvent {
        next += 1
        let event = CalendarEvent(id: "new-\(next)", title: draft.title, start: draft.start, end: draft.end,
                                  calendarID: calendarID, calendarTitle: TestCalendar.title)
        events.append(event)
        return event
    }
    func move(eventID: String, start: Date, end: Date) async throws -> CalendarEvent {
        guard let i = events.firstIndex(where: { $0.id == eventID }) else { throw ToolRunError.failed("x", message: "gone") }
        events[i].start = start
        events[i].end = end
        return events[i]
    }
    func remove(eventID: String) async throws { events.removeAll { $0.id == eventID } }
}

struct PretendContacts: ContactsStore {
    let people: [Person]
    func people(named name: String) async throws -> [Person] {
        people.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }
}

struct NoAccessCalendar: CalendarStore {
    func events(from: Date, to: Date) async throws -> [CalendarEvent] { throw ToolRunError.noAccess("calendar") }
    func event(id: String) async throws -> CalendarEvent? { throw ToolRunError.noAccess("calendar") }
    func testCalendarID() async throws -> String { throw ToolRunError.noAccess("calendar") }
    func add(_ draft: EventDraft, to calendarID: String) async throws -> CalendarEvent { throw ToolRunError.noAccess("calendar") }
    func move(eventID: String, start: Date, end: Date) async throws -> CalendarEvent { throw ToolRunError.noAccess("calendar") }
    func remove(eventID: String) async throws { throw ToolRunError.noAccess("calendar") }
}

/// Says yes to everything. Calendar tools never ask anyway.
struct Yes: Approver { func approve(_ step: StepPreview) async -> Bool { true } }

// MARK: - Helpers

let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2027-03-04 (a Thursday) at the given hour and minute, UTC.
func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
    utc.date(from: DateComponents(year: 2027, month: 3, day: day, hour: hour, minute: minute))!
}

func iso(_ date: Date) -> String { date.formatted(.iso8601) }

func meeting(_ id: String, _ start: Date, _ end: Date, calendar: String = "work", busy: Bool = true, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, isBusy: busy,
                  calendarID: calendar, calendarTitle: calendar)
}

func calendarRunner(_ store: any CalendarStore) throws -> JobRunner {
    var r = ToolRegistry()
    try r.register(FreeTimeTool(store: store))
    try r.register(FindEventsTool(store: store))
    try r.register(AddEventTool(store: store))
    try r.register(MoveEventTool(store: store))
    try r.register(FindPersonTool(store: PretendContacts(people: [
        Person(id: "1", name: "Maria Papadopoulou", phones: ["+30 690 000 0000"]),
        Person(id: "2", name: "Maria Lopez", emails: ["maria@example.com"]),
        Person(id: "3", name: "Joe Bloggs"),
    ])))
    return JobRunner(registry: r, approver: Yes(), context: ToolContext(platform: .macOS))
}

// MARK: - Free time

@Suite("Free time")
struct FreeTimeTests {
    let hours = WorkingHours(startHour: 9, endHour: 18)

    func slots(_ events: [CalendarEvent], minutes: Int = 30, from: Date = at(0), to: Date = at(0, day: 5)) -> [TimeSlot] {
        FreeTime.slots(from: from, to: to, events: events, minimum: TimeInterval(minutes * 60), hours: hours, calendar: utc)
    }

    @Test func anEmptyDayIsOneSlotOfWorkingHours() {
        #expect(slots([]) == [TimeSlot(start: at(9), end: at(18))])
    }

    @Test func meetingsSplitTheDay() {
        let s = slots([meeting("a", at(10), at(11)), meeting("b", at(14), at(15))])
        #expect(s == [TimeSlot(start: at(9), end: at(10)), TimeSlot(start: at(11), end: at(14)), TimeSlot(start: at(15), end: at(18))])
    }

    @Test func overlappingMeetingsMerge() {
        let s = slots([meeting("a", at(10), at(12)), meeting("b", at(11), at(13))])
        #expect(s == [TimeSlot(start: at(9), end: at(10)), TimeSlot(start: at(13), end: at(18))])
    }

    @Test func gapsShorterThanAskedAreSkipped() {
        let s = slots([meeting("a", at(9, 30), at(10)), meeting("b", at(10, 15), at(18))], minutes: 30)
        #expect(s == [TimeSlot(start: at(9), end: at(9, 30))])
    }

    @Test func allDayAndFreeEventsDontBlockTime() {
        let s = slots([meeting("holiday", at(0), at(0, day: 5), allDay: true), meeting("focus", at(10), at(11), busy: false)])
        #expect(s == [TimeSlot(start: at(9), end: at(18))])
    }

    @Test func meetingsOverTheEdgesOfTheDayAreClipped() {
        let s = slots([meeting("early", at(8), at(9, 30)), meeting("late", at(17), at(20))])
        #expect(s == [TimeSlot(start: at(9, 30), end: at(17))])
    }

    @Test func theSearchStartsNoEarlierThanAsked() {
        let s = slots([], from: at(15))
        #expect(s == [TimeSlot(start: at(15), end: at(18))])
    }

    @Test func severalDays() {
        let s = slots([], from: at(0), to: at(0, day: 6))
        #expect(s == [TimeSlot(start: at(9), end: at(18)), TimeSlot(start: at(9, day: 5), end: at(18, day: 5))])
    }
}

// MARK: - Calendar and contacts tools

@Suite("Calendar and contacts tools")
struct CalendarToolsTests {
    @Test func addPutsTheEventInTheTestCalendarAndUndoRemovesIt() async throws {
        let store = PretendCalendar()
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: AddEventTool.name, argumentsJSON: Data(
            #"{"title":"Design review","start":"\#(iso(at(15)))","end":"\#(iso(at(16)))"}"#.utf8))])
        #expect(result.outcome == .completed)
        #expect(await store.events.map(\.calendarID) == [PretendCalendar.testID])
        await runner.undoAll()
        #expect(await store.events.isEmpty)
    }

    @Test func moveWorksInTheTestCalendarAndUndoMovesItBack() async throws {
        let store = PretendCalendar([meeting("m", at(15), at(16), calendar: PretendCalendar.testID)])
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: MoveEventTool.name, argumentsJSON: Data(
            #"{"eventID":"m","start":"\#(iso(at(10, day: 5)))","end":"\#(iso(at(11, day: 5)))"}"#.utf8))])
        #expect(result.outcome == .completed)
        #expect(await store.events.first?.start == at(10, day: 5))
        await runner.undoAll()
        #expect(await store.events.first?.start == at(15))
        #expect(await store.events.first?.end == at(16))
    }

    @Test func movingARealMeetingIsRefusedBeforeAnythingRuns() async throws {
        let store = PretendCalendar([meeting("real", at(15), at(16), calendar: "work")])
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: MoveEventTool.name, argumentsJSON: Data(
            #"{"eventID":"real","start":"\#(iso(at(10)))","end":"\#(iso(at(11)))"}"#.utf8))])
        guard case .refused(.notAllowed(MoveEventTool.name, _)) = result.outcome else {
            Issue.record("expected refusal, got \(result.outcome)")
            return
        }
        #expect(await store.events.first?.start == at(15))
    }

    @Test func freeTimeReadsEveryCalendar() async throws {
        let store = PretendCalendar([meeting("a", at(9), at(17), calendar: "work"), meeting("b", at(17), at(17, 30), calendar: "home")])
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: FreeTimeTool.name, argumentsJSON: Data(
            #"{"from":"\#(iso(at(0)))","to":"\#(iso(at(0, day: 5)))","minutes":30}"#.utf8))])
        let output = try ToolJSON.decoder.decode(FreeTimeTool.Output.self, from: try #require(result.outputs["1"]))
        // Times are in the Mac's own time zone, so only check the shape: one slot, after both meetings.
        #expect(output.slots.count <= 1)
        #expect(output.slots.allSatisfy { $0.start >= at(17, 30) || $0.end <= at(9) })
    }

    @Test func findEventsMatchesPartOfTheTitle() async throws {
        let store = PretendCalendar([meeting("Design review", at(15), at(16)), meeting("Lunch", at(12), at(13))])
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: FindEventsTool.name, argumentsJSON: Data(
            #"{"from":"\#(iso(at(0)))","to":"\#(iso(at(0, day: 5)))","title":"design"}"#.utf8))])
        let output = try ToolJSON.decoder.decode(FindEventsTool.Output.self, from: try #require(result.outputs["1"]))
        #expect(output.events.map(\.title) == ["Design review"])
    }

    @Test func findPersonReturnsEveryMatchAndNeverGuesses() async throws {
        let runner = try calendarRunner(PretendCalendar())
        let result = await runner.run([ToolCall(id: "1", toolName: FindPersonTool.name, argumentsJSON: Data(#"{"name":"Maria"}"#.utf8))])
        let output = try ToolJSON.decoder.decode(FindPersonTool.Output.self, from: try #require(result.outputs["1"]))
        #expect(output.people.map(\.name) == ["Maria Papadopoulou", "Maria Lopez"])
    }

    @Test func noCalendarAccessIsReportedAsSuch() async throws {
        let runner = try calendarRunner(NoAccessCalendar())
        let result = await runner.run([ToolCall(id: "1", toolName: FreeTimeTool.name, argumentsJSON: Data(
            #"{"from":"\#(iso(at(0)))","to":"\#(iso(at(0, day: 5)))","minutes":30}"#.utf8))])
        #expect(result.outcome == .failed(id: "1", .noAccess("calendar")))
    }

    @Test func anEventThatEndsBeforeItStartsIsRefused() async throws {
        let store = PretendCalendar()
        let runner = try calendarRunner(store)
        let result = await runner.run([ToolCall(id: "1", toolName: AddEventTool.name, argumentsJSON: Data(
            #"{"title":"Backwards","start":"\#(iso(at(16)))","end":"\#(iso(at(15)))"}"#.utf8))])
        #expect(result.outcome == .refused(.badArguments(AddEventTool.name)))
        #expect(await store.events.isEmpty)
    }
}
