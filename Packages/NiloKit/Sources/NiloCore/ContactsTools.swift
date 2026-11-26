import Foundation

// Contacts: find a person by name. Read only.

public struct Person: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var phones: [String]
    public var emails: [String]

    public init(id: String, name: String, phones: [String] = [], emails: [String] = []) {
        self.id = id
        self.name = name
        self.phones = phones
        self.emails = emails
    }
}

/// Where contacts come from. The Contacts framework in the apps, a pretend book in tests.
public protocol ContactsStore: Sendable {
    func people(named name: String) async throws -> [Person]
    /// The person's own card ("My Card"), if they've set one.
    func me() async throws -> Person?
}

public extension ContactsStore {
    func me() async throws -> Person? { nil }
}

public struct FindPersonTool: AssistantTool {
    public struct Input: Codable, Sendable {
        public var name: String
        public init(name: String) { self.name = name }
    }

    /// Every match. Several means the person chooses; Nilo never guesses.
    public struct Output: Codable, Sendable {
        public var people: [Person]
    }

    public static let name = "contacts.find_person"
    public static let summary = "Finds people in Contacts by name, with their phone numbers and email addresses."
    public static let risk = Risk.read
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let store: any ContactsStore

    public init(store: any ContactsStore) {
        self.store = store
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        guard !input.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ToolRunError.badArguments(Self.name) }
        return ToolPreview(title: "Look up \(input.name) in Contacts")
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Output {
        Output(people: try await store.people(named: input.name.trimmingCharacters(in: .whitespaces)))
    }
}
