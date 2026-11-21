import Foundation

/// A single thing Nilo remembers, in its own words, exactly as the user sees it.
public struct MemoryItem: Identifiable, Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case told, learned, person, job }

    public var id: UUID
    public var text: String
    public var kind: Kind
    /// Contacts or EventKit identifier when linked. Never a copy of the source.
    public var sourceIdentifier: String?
    public var createdAt: Date
    /// Set for jobs (30 days). Nil when pinned or permanent.
    public var expiresAt: Date?

    public init(id: UUID = UUID(), text: String, kind: Kind, sourceIdentifier: String? = nil,
                createdAt: Date = .now, expiresAt: Date? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.sourceIdentifier = sourceIdentifier
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public protocol MemoryStore: Sendable {
    /// The few lines a job needs, ranked on device. Never the whole store.
    func relevant(to request: AssistantRequest, limit: Int) async -> [MemoryItem]
    /// Asks the user. Saves only on yes. Nothing is learned silently.
    func propose(_ item: MemoryItem) async
    /// Removes the item on every device.
    func forget(_ id: UUID) async
    func all() async -> [MemoryItem]
}
