import Foundation

// The tool runner: carries out a job one step at a time and enforces the approval rules.
//
// Whatever a model asks for, it comes through here. The rules live in code:
// - Every step is checked before anything runs: unknown tool, details that don't fit, or not
//   on this device, and the whole job is refused. Nothing half-runs on a bad request.
// - `.read` runs at once. `.change` runs and keeps its undo. `.send` and `.delete` stop and
//   wait for an explicit yes, showing the exact preview. No means that step and everything
//   after it don't run; changes already made stay, with undo available.
// - Undo takes changes back in reverse order.
// - No setting lowers any of this.

// MARK: - Errors

public enum ToolRunError: Error, Sendable, Equatable {
    case unknownTool(String)
    case badArguments(String)
    case notOnThisPlatform(String)
    /// A `.change` tool that can't be undone. Refused at registration.
    case changeNeedsUndo(String)
    case duplicateTool(String)
    /// The tool itself failed while running.
    case failed(String, message: String)
    /// Nilo has no access to this kind of data (calendar, contacts). The person can turn it on.
    case noAccess(String)
    /// A rule forbids this, e.g. writing outside the test calendar.
    case notAllowed(String, reason: String)
}

/// Dates travel as ISO 8601 text with a time zone, the way a model writes them.
public enum ToolJSON {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

// MARK: - Registry

/// Every tool Nilo can run, by name.
public struct ToolRegistry: Sendable {
    private var tools: [String: AnyTool] = [:]

    public init() {}

    /// Registers a tool that can't be undone. Refuses a `.change` tool: changes must be reversible.
    public mutating func register<T: AssistantTool>(_ tool: T) throws {
        guard T.risk != .change else { throw ToolRunError.changeNeedsUndo(T.name) }
        try add(AnyTool(tool, undo: nil))
    }

    /// Registers a tool whose effect can be taken back.
    public mutating func register<T: ReversibleTool>(_ tool: T) throws {
        try add(AnyTool(tool, undo: { tool, input, output, context in try await tool.undo(input, output: output, in: context) }))
    }

    public var specs: [ToolSpec] {
        tools.values.map { ToolSpec(name: $0.name, summary: $0.summary, risk: $0.risk) }.sorted { $0.name < $1.name }
    }

    func tool(named name: String) -> AnyTool? { tools[name] }

    private mutating func add(_ tool: AnyTool) throws {
        guard tools[tool.name] == nil else { throw ToolRunError.duplicateTool(tool.name) }
        tools[tool.name] = tool
    }
}

/// A tool with its types hidden, so the registry can hold many kinds.
struct AnyTool: Sendable {
    let name: String
    let summary: String
    let risk: Risk
    let platforms: Set<Platform>
    /// Decodes the details and gets the preview, without changing anything.
    let prepare: @Sendable (Data, ToolContext) async throws -> PreparedStep

    init<T: AssistantTool>(
        _ tool: T,
        undo: (@Sendable (T, T.Input, T.Output, ToolContext) async throws -> Void)?
    ) {
        name = T.name
        summary = T.summary
        risk = T.risk
        platforms = T.platforms
        prepare = { data, context in
            let input: T.Input
            do {
                input = try ToolJSON.decoder.decode(T.Input.self, from: data)
            } catch {
                throw ToolRunError.badArguments(T.name)
            }
            let preview = try await tool.preview(input, in: context)
            return PreparedStep(name: T.name, risk: T.risk, preview: preview) {
                let output = try await tool.run(input, in: context)
                let outputJSON = (try? ToolJSON.encoder.encode(output)) ?? Data()
                guard let undo else { return (outputJSON, nil) }
                return (outputJSON, { try await undo(tool, input, output, context) })
            }
        }
    }
}

/// One checked step, ready to run.
struct PreparedStep: Sendable {
    let name: String
    let risk: Risk
    let preview: ToolPreview
    /// Runs the tool. Returns its output, and how to undo it for reversible tools.
    let run: @Sendable () async throws -> (Data, (@Sendable () async throws -> Void)?)
}

// MARK: - Approval

/// Shows a step's exact preview and waits for the person. The app implements this (the plan
/// card, 2g). Return true only on an explicit yes.
public protocol Approver: Sendable {
    func approve(_ step: StepPreview) async -> Bool
}

public struct StepPreview: Sendable, Equatable {
    public let id: String
    public let toolName: String
    public let risk: Risk
    public let preview: ToolPreview
}

// MARK: - Running

public enum RunEvent: Sendable, Equatable {
    /// A step began running. For changes, `preview` is what the person sees, with undo.
    case started(StepPreview)
    /// A send or delete is waiting for the person.
    case waitingForApproval(StepPreview)
    case finished(id: String)
    case declined(id: String)
    case failed(id: String, ToolRunError)
}

public struct JobResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case completed
        /// Nothing ran: a step was refused before the job started.
        case refused(ToolRunError)
        /// The person said no to this step. It and everything after it didn't run.
        case declined(id: String)
        case failed(id: String, ToolRunError)
    }

    public var outcome: Outcome
    /// Steps that ran, in order.
    public var ran: [String]
    /// What each step that ran returned, as JSON, by step id. A recipe reads these to fill in
    /// the next steps.
    public var outputs: [String: Data] = [:]
    /// True when some changes can be undone.
    public var canUndo: Bool
}

public actor JobRunner {
    private let registry: ToolRegistry
    private let policy: ApprovalPolicy
    private let approver: Approver
    private let context: ToolContext
    /// Undo for each change made, oldest first.
    private var undoStack: [(id: String, undo: @Sendable () async throws -> Void)] = []

    public init(registry: ToolRegistry, approver: Approver, context: ToolContext, policy: ApprovalPolicy = ApprovalPolicy()) {
        self.registry = registry
        self.approver = approver
        self.context = context
        self.policy = policy
    }

    /// Runs a job's steps in order. `events` reports progress as it happens.
    public func run(_ calls: [ToolCall], events: @Sendable (RunEvent) -> Void = { _ in }) async -> JobResult {
        // 1. Check every step before running any.
        var steps: [(call: ToolCall, step: PreparedStep)] = []
        for call in calls {
            guard let tool = registry.tool(named: call.toolName) else {
                return JobResult(outcome: .refused(.unknownTool(call.toolName)), ran: [], canUndo: !undoStack.isEmpty)
            }
            guard tool.platforms.contains(context.platform) else {
                return JobResult(outcome: .refused(.notOnThisPlatform(call.toolName)), ran: [], canUndo: !undoStack.isEmpty)
            }
            do {
                steps.append((call, try await tool.prepare(call.argumentsJSON, context)))
            } catch let error as ToolRunError {
                return JobResult(outcome: .refused(error), ran: [], canUndo: !undoStack.isEmpty)
            } catch {
                let refused = ToolRunError.failed(call.toolName, message: error.localizedDescription)
                return JobResult(outcome: .refused(refused), ran: [], canUndo: !undoStack.isEmpty)
            }
        }

        // 2. Run them, asking where the rules say so.
        var ran: [String] = []
        var outputs: [String: Data] = [:]
        for (call, step) in steps {
            let shown = StepPreview(id: call.id, toolName: step.name, risk: step.risk, preview: step.preview)
            switch policy.decision(for: step.risk) {
            case .runNow, .preview:
                events(.started(shown))
            case .askFirst:
                events(.waitingForApproval(shown))
                guard await approver.approve(shown) else {
                    events(.declined(id: call.id))
                    return JobResult(outcome: .declined(id: call.id), ran: ran, outputs: outputs, canUndo: !undoStack.isEmpty)
                }
                events(.started(shown))
            }
            do {
                let (output, undo) = try await step.run()
                if let undo { undoStack.append((call.id, undo)) }
                ran.append(call.id)
                outputs[call.id] = output
                events(.finished(id: call.id))
            } catch {
                let failure = (error as? ToolRunError) ?? .failed(step.name, message: error.localizedDescription)
                events(.failed(id: call.id, failure))
                return JobResult(outcome: .failed(id: call.id, failure), ran: ran, outputs: outputs, canUndo: !undoStack.isEmpty)
            }
        }
        return JobResult(outcome: .completed, ran: ran, outputs: outputs, canUndo: !undoStack.isEmpty)
    }

    /// Takes back every change, newest first. Keeps going if one fails, and reports those.
    @discardableResult
    public func undoAll() async -> [ToolRunError] {
        var failures: [ToolRunError] = []
        while let last = undoStack.popLast() {
            do {
                try await last.undo()
            } catch {
                failures.append(.failed(last.id, message: error.localizedDescription))
            }
        }
        return failures
    }
}
