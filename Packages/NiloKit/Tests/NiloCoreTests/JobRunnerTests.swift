import Foundation
import Testing
@testable import NiloCore

// MARK: - Pretend tools

/// Everything the pretend tools do, in order, so tests can see what really ran.
actor Log {
    private(set) var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}

struct Thing: Codable, Sendable { var name: String }
struct Note: Codable, Sendable { var to: [String]; var text: String }
struct Done: Codable, Sendable { var ok = true }

struct LookUp: AssistantTool {
    static let name = "test.look_up"
    static let summary = "Looks something up."
    static let risk = Risk.read
    static let platforms: Set<Platform> = [.macOS]
    let log: Log
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview { ToolPreview(title: "Look up \(input.name)") }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { await log.add("look up \(input.name)"); return Done() }
}

struct AddThing: ReversibleTool {
    static let name = "test.add"
    static let summary = "Adds a thing."
    static let risk = Risk.change
    static let platforms: Set<Platform> = [.macOS]
    let log: Log
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview { ToolPreview(title: "Add \(input.name)") }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { await log.add("add \(input.name)"); return Done() }
    func undo(_ input: Thing, output: Done, in context: ToolContext) async throws { await log.add("undo add \(input.name)") }
}

/// A change with no undo. The registry must refuse it.
struct ChangeWithoutUndo: AssistantTool {
    static let name = "test.change_forever"
    static let summary = "Changes something for good."
    static let risk = Risk.change
    static let platforms: Set<Platform> = [.macOS]
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview { ToolPreview(title: "Change") }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { Done() }
}

struct SendNote: AssistantTool {
    static let name = "test.send"
    static let summary = "Sends a note."
    static let risk = Risk.send
    static let platforms: Set<Platform> = [.macOS]
    let log: Log
    func preview(_ input: Note, in context: ToolContext) async throws -> ToolPreview {
        ToolPreview(title: "Send a note", recipients: input.to, text: input.text)
    }
    func run(_ input: Note, in context: ToolContext) async throws -> Done { await log.add("send \(input.text)"); return Done() }
}

struct RemoveThing: AssistantTool {
    static let name = "test.remove"
    static let summary = "Removes a thing."
    static let risk = Risk.delete
    static let platforms: Set<Platform> = [.macOS]
    let log: Log
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview {
        ToolPreview(title: "Remove", items: [input.name])
    }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { await log.add("remove \(input.name)"); return Done() }
}

struct Broken: AssistantTool {
    struct Oops: Error {}
    static let name = "test.broken"
    static let summary = "Always fails."
    static let risk = Risk.read
    static let platforms: Set<Platform> = [.macOS]
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview { ToolPreview(title: "Break") }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { throw Oops() }
}

struct PhoneOnly: AssistantTool {
    static let name = "test.phone_only"
    static let summary = "Only on iPhone."
    static let risk = Risk.read
    static let platforms: Set<Platform> = [.iOS]
    func preview(_ input: Thing, in context: ToolContext) async throws -> ToolPreview { ToolPreview(title: "Phone") }
    func run(_ input: Thing, in context: ToolContext) async throws -> Done { Done() }
}

/// Answers yes or no, and remembers exactly what it was shown.
actor PretendPerson: Approver {
    private let answer: Bool
    private(set) var shown: [StepPreview] = []
    init(says answer: Bool) { self.answer = answer }
    func approve(_ step: StepPreview) async -> Bool {
        shown.append(step)
        return answer
    }
}

/// Collects events from the runner.
final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [RunEvent] = []
    func add(_ event: RunEvent) { lock.withLock { list.append(event) } }
    var all: [RunEvent] { lock.withLock { list } }
}

// MARK: - Helpers

func call(_ id: String, _ tool: String, _ json: String) -> ToolCall {
    ToolCall(id: id, toolName: tool, argumentsJSON: Data(json.utf8))
}

func registry(_ log: Log) throws -> ToolRegistry {
    var r = ToolRegistry()
    try r.register(LookUp(log: log))
    try r.register(AddThing(log: log))
    try r.register(SendNote(log: log))
    try r.register(RemoveThing(log: log))
    try r.register(Broken())
    try r.register(PhoneOnly())
    return r
}

func runner(_ log: Log, says answer: Bool) throws -> (JobRunner, PretendPerson) {
    let person = PretendPerson(says: answer)
    return (JobRunner(registry: try registry(log), approver: person, context: ToolContext(platform: .macOS)), person)
}

// MARK: - Tests

@Suite("Tool runner")
struct JobRunnerTests {
    @Test func readsRunWithoutAsking() async throws {
        let log = Log()
        let (runner, person) = try runner(log, says: false)
        let result = await runner.run([call("1", "test.look_up", #"{"name":"Maria"}"#)])
        #expect(result.outcome == .completed)
        #expect(await log.lines == ["look up Maria"])
        #expect(await person.shown.isEmpty)
    }

    @Test func changesRunWithoutAskingAndCanBeUndone() async throws {
        let log = Log()
        let (runner, person) = try runner(log, says: false)
        let result = await runner.run([call("1", "test.add", #"{"name":"Design review"}"#)])
        #expect(result.outcome == .completed)
        #expect(result.canUndo)
        #expect(await person.shown.isEmpty)
        #expect(await runner.undoAll().isEmpty)
        #expect(await log.lines == ["add Design review", "undo add Design review"])
    }

    @Test func sendAsksWithTheExactTextAndEveryRecipient() async throws {
        let log = Log()
        let (runner, person) = try runner(log, says: true)
        let result = await runner.run([call("1", "test.send", #"{"to":["Maria","Joe"],"text":"See you at 3."}"#)])
        #expect(result.outcome == .completed)
        let shown = try #require(await person.shown.first)
        #expect(shown.risk == .send)
        #expect(shown.preview.text == "See you at 3.")
        #expect(shown.preview.recipients == ["Maria", "Joe"])
        #expect(await log.lines == ["send See you at 3."])
    }

    @Test func noMeansTheSendNeverRunsAndNothingAfterIt() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: false)
        let result = await runner.run([
            call("1", "test.add", #"{"name":"Design review"}"#),
            call("2", "test.send", #"{"to":["Maria"],"text":"See you at 3."}"#),
            call("3", "test.look_up", #"{"name":"after"}"#),
        ])
        #expect(result.outcome == .declined(id: "2"))
        #expect(result.ran == ["1"])
        // The change made before the no stays, and can be undone.
        #expect(result.canUndo)
        #expect(await log.lines == ["add Design review"])
    }

    @Test func deleteAlwaysAsksAndListsEveryItem() async throws {
        let log = Log()
        let (runner, person) = try runner(log, says: false)
        let result = await runner.run([call("1", "test.remove", #"{"name":"Old notes"}"#)])
        #expect(result.outcome == .declined(id: "1"))
        #expect(await person.shown.first?.preview.items == ["Old notes"])
        #expect(await log.lines.isEmpty)
    }

    @Test func undoGoesNewestFirst() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        _ = await runner.run([
            call("1", "test.add", #"{"name":"A"}"#),
            call("2", "test.add", #"{"name":"B"}"#),
            call("3", "test.add", #"{"name":"C"}"#),
        ])
        await runner.undoAll()
        #expect(await log.lines == ["add A", "add B", "add C", "undo add C", "undo add B", "undo add A"])
        #expect(await runner.run([]).canUndo == false)
    }

    @Test func anUnknownToolIsRefusedBeforeAnythingRuns() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        let result = await runner.run([
            call("1", "test.add", #"{"name":"A"}"#),
            call("2", "test.launch_rockets", #"{}"#),
        ])
        #expect(result.outcome == .refused(.unknownTool("test.launch_rockets")))
        #expect(await log.lines.isEmpty)
    }

    @Test func detailsThatDontFitAreRefusedBeforeAnythingRuns() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        let result = await runner.run([
            call("1", "test.add", #"{"name":"A"}"#),
            call("2", "test.send", #"{"text":"no recipients"}"#),
        ])
        #expect(result.outcome == .refused(.badArguments("test.send")))
        #expect(await log.lines.isEmpty)
    }

    @Test func aToolForAnotherDeviceIsRefused() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        let result = await runner.run([call("1", "test.phone_only", #"{"name":"A"}"#)])
        #expect(result.outcome == .refused(.notOnThisPlatform("test.phone_only")))
    }

    @Test func aChangeWithoutUndoCannotBeRegistered() {
        var r = ToolRegistry()
        #expect(throws: ToolRunError.changeNeedsUndo("test.change_forever")) {
            try r.register(ChangeWithoutUndo())
        }
    }

    @Test func twoToolsCannotShareAName() throws {
        var r = ToolRegistry()
        try r.register(LookUp(log: Log()))
        #expect(throws: ToolRunError.duplicateTool("test.look_up")) {
            try r.register(LookUp(log: Log()))
        }
    }

    @Test func aFailingStepStopsTheJob() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        let result = await runner.run([
            call("1", "test.add", #"{"name":"A"}"#),
            call("2", "test.broken", #"{"name":"x"}"#),
            call("3", "test.add", #"{"name":"B"}"#),
        ])
        guard case .failed(id: "2", _) = result.outcome else {
            Issue.record("expected the job to fail at step 2, got \(result.outcome)")
            return
        }
        #expect(result.ran == ["1"])
        #expect(await log.lines == ["add A"])
    }

    @Test func eventsTellTheStoryInOrder() async throws {
        let log = Log()
        let (runner, _) = try runner(log, says: true)
        let events = Events()
        _ = await runner.run([
            call("1", "test.add", #"{"name":"A"}"#),
            call("2", "test.send", #"{"to":["Maria"],"text":"Hi"}"#),
        ], events: { events.add($0) })
        let story = events.all.map { event -> String in
            switch event {
            case .started(let s): "started \(s.id)"
            case .waitingForApproval(let s): "waiting \(s.id)"
            case .finished(let id): "finished \(id)"
            case .declined(let id): "declined \(id)"
            case .failed(let id, _): "failed \(id)"
            }
        }
        #expect(story == ["started 1", "finished 1", "waiting 2", "started 2", "finished 2"])
    }
}
