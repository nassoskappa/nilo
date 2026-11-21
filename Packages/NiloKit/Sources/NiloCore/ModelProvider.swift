import Foundation

/// Every model sits behind this protocol. The router, the UI and the tools
/// only talk to `ModelProvider`, so adding a provider touches one file.
public protocol ModelProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: Capabilities { get }
    var cost: CostClass { get }

    func availability() async -> Availability
    func respond(to request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error>
}

public enum ProviderID: String, Sendable, Codable {
    case onDevice        // Apple Foundation Models
    case claudeOwnKey    // Claude API, user's own key (v1)
    case claudeCredits   // Claude API through our proxy (later)
}

public struct Capabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let tools       = Capabilities(rawValue: 1 << 0)
    public static let vision      = Capabilities(rawValue: 1 << 1)
    public static let longContext = Capabilities(rawValue: 1 << 2)
    public static let streaming   = Capabilities(rawValue: 1 << 3)
}

public enum CostClass: Sendable { case free, metered }

public enum Availability: Sendable, Equatable {
    case ready
    case noKey
    case noCredits
    case unsupportedDevice
    case offline
}

public struct AssistantRequest: Sendable {
    public var messages: [Message]
    public var tools: [ToolSpec]
    public var context: ContextPack
    public var budget: Budget

    public init(messages: [Message], tools: [ToolSpec] = [], context: ContextPack = .init(), budget: Budget = .init()) {
        self.messages = messages
        self.tools = tools
        self.context = context
        self.budget = budget
    }
}

public struct Message: Sendable, Codable, Equatable {
    public enum Role: String, Sendable, Codable { case user, assistant, tool }
    public var role: Role
    public var text: String
    public init(role: Role, text: String) { self.role = role; self.text = text }
}

/// The smallest context a job needs. Never the whole memory store.
public struct ContextPack: Sendable {
    public var memories: [MemoryItem]
    public var selection: String?
    public init(memories: [MemoryItem] = [], selection: String? = nil) {
        self.memories = memories
        self.selection = selection
    }
}

public struct Budget: Sendable {
    public var maxOutputTokens: Int
    public var maxToolSteps: Int
    public init(maxOutputTokens: Int = 2_048, maxToolSteps: Int = 8) {
        self.maxOutputTokens = maxOutputTokens
        self.maxToolSteps = maxToolSteps
    }
}

/// One stream shape for every provider, so the UI never knows which model answered.
public enum AssistantEvent: Sendable {
    case text(String)
    case toolCall(ToolCall)
    case needsApproval(ToolCall)
    case usage(TokenUsage)
    case done
}

public struct ToolCall: Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let argumentsJSON: Data
    public init(id: String, toolName: String, argumentsJSON: Data) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

public struct TokenUsage: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
