#if os(macOS) || os(iOS)
import Contacts
import EventKit
import Foundation

/// The person's real calendars, through EventKit. Asks for access the first time it's needed.
public actor EventKitCalendar: CalendarStore {
    private let store = EKEventStore()
    private var granted = false

    public init() {}

    private func access() async throws {
        if granted { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            granted = true
        case .notDetermined:
            granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else { throw ToolRunError.noAccess("calendar") }
        default:
            throw ToolRunError.noAccess("calendar")
        }
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        try await access()
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map(Self.convert)
    }

    public func event(id: String) async throws -> CalendarEvent? {
        try await access()
        return store.event(withIdentifier: id).map(Self.convert)
    }

    public func testCalendarID() async throws -> String {
        try await access()
        if let existing = store.calendars(for: .event).first(where: {
            $0.title == TestCalendar.title && $0.allowsContentModifications
        }) {
            return existing.calendarIdentifier
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = TestCalendar.title
        calendar.cgColor = CGColor(red: 1, green: 0.69, blue: 0, alpha: 1) // amber
        // Prefer where new events usually go (often iCloud), else a calendar on this device.
        let sources = [store.defaultCalendarForNewEvents?.source]
            + store.sources.filter { $0.sourceType == .calDAV } .map(Optional.some)
            + store.sources.filter { $0.sourceType == .local }.map(Optional.some)
        for case let source? in sources {
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                return calendar.calendarIdentifier
            } catch {
                continue
            }
        }
        throw ToolRunError.failed("calendar", message: "Couldn't create the \(TestCalendar.title) calendar.")
    }

    public func add(_ draft: EventDraft, to calendarID: String) async throws -> CalendarEvent {
        try await access()
        guard let calendar = store.calendar(withIdentifier: calendarID) else {
            throw ToolRunError.failed("calendar", message: "The \(TestCalendar.title) calendar is missing.")
        }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
        event.location = draft.location
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return Self.convert(event)
    }

    public func move(eventID: String, start: Date, end: Date) async throws -> CalendarEvent {
        try await access()
        guard let event = store.event(withIdentifier: eventID) else {
            throw ToolRunError.failed("calendar", message: "That event no longer exists.")
        }
        event.startDate = start
        event.endDate = end
        try store.save(event, span: .thisEvent, commit: true)
        return Self.convert(event)
    }

    public func remove(eventID: String) async throws {
        try await access()
        guard let event = store.event(withIdentifier: eventID) else { return } // already gone
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isBusy: event.availability != .free,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? ""
        )
    }
}

/// The person's real contacts. Asks for access the first time it's needed.
public actor ContactsBook: ContactsStore {
    private let store = CNContactStore()

    public init() {}

    private func access() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            guard granted else { throw ToolRunError.noAccess("contacts") }
        default:
            throw ToolRunError.noAccess("contacts")
        }
    }

    private static var keys: [CNKeyDescriptor] { [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
    ] as [CNKeyDescriptor] }

    public func people(named name: String) async throws -> [Person] {
        try await access()
        let found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: Self.keys)
        return found.map(Self.person)
    }

    public func me() async throws -> Person? {
        try await access()
        #if os(macOS)
        return (try? store.unifiedMeContactWithKeys(toFetch: Self.keys)).map(Self.person)
        #else
        return nil
        #endif
    }

    private static func person(_ contact: CNContact) -> Person {
        let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return Person(
            id: contact.identifier,
            name: full.isEmpty ? contact.organizationName : full,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String }
        )
    }
}
#endif
