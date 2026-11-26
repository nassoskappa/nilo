import Foundation

/// Each action is defined once and exposed as a Claude tool, a Foundation
/// Models tool, an App Intent and (on Mac) an MCP tool.
public protocol AssistantTool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    /// Stable name, e.g. "calendar.move_event".
    static var name: String { get }
    /// What the model reads to decide when to use it. One or two sentences.
    static var summary: String { get }
    /// Decides how approval works. See `Risk`.
    static var risk: Risk { get }
    static var platforms: Set<Platform> { get }

    /// Exactly what running it would do, in words the person approves. For `.send` this
    /// carries the exact text and every recipient; for `.delete`, every item that goes.
    /// Must not change anything.
    func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview

    func run(_ input: Input, in context: ToolContext) async throws -> Output
}

/// A tool whose effect can be taken back. Every `.change` tool must be one: the runner
/// refuses to register a change it can't undo.
public protocol ReversibleTool: AssistantTool {
    func undo(_ input: Input, output: Output, in context: ToolContext) async throws
}

/// What the person sees before (or, for changes, while) a step runs.
public struct ToolPreview: Sendable, Equatable, Codable {
    /// One line, result first. "Add Design review, Thursday 3 to 4 pm".
    public var title: String
    /// Extra lines, if any.
    public var details: [String]
    /// Everyone who will receive something. Never shortened.
    public var recipients: [String]
    /// The exact text that will be sent, word for word.
    public var text: String?
    /// Every item that will be deleted. Never shortened.
    public var items: [String]

    public init(title: String, details: [String] = [], recipients: [String] = [], text: String? = nil, items: [String] = []) {
        self.title = title
        self.details = details
        self.recipients = recipients
        self.text = text
        self.items = items
    }
}

/// The approval engine reads this. No setting can lower it.
public enum Risk: Int, Sendable, Comparable, Codable {
    case read = 0     // runs at once
    case change = 1   // preview with undo
    case send = 2     // always asks, shows exact text and recipients
    case delete = 3   // always asks, shows exactly what goes

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    public var needsExplicitApproval: Bool { self >= .send }
}

public enum Platform: String, Sendable, Codable, CaseIterable {
    case macOS, iOS, iPadOS, watchOS, tvOS
}

public struct ToolContext: Sendable {
    public var platform: Platform
    public init(platform: Platform) { self.platform = platform }
}

/// What a provider receives to describe a tool.
public struct ToolSpec: Sendable {
    public var name: String
    public var summary: String
    public var risk: Risk
    public init(name: String, summary: String, risk: Risk) {
        self.name = name
        self.summary = summary
        self.risk = risk
    }

    public init<T: AssistantTool>(_ tool: T.Type) {
        self.init(name: T.name, summary: T.summary, risk: T.risk)
    }
}
