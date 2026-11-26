import Foundation
import Testing
@testable import NiloCore

@Suite("Plans")
struct PlanTests {
    let addA = call("1", "test.add", #"{"name":"A"}"#)
    let sendHi = call("2", "test.send", #"{"to":["Maria"],"text":"See you at 3."}"#)

    @Test func previewingRunsNothing() async throws {
        let log = Log()
        let (runner, person) = try runner(log, says: true)
        let check = await runner.preview([addA, sendHi])
        guard case .ready(let steps) = check else {
            Issue.record("expected a ready plan, got \(check)")
            return
        }
        #expect(steps.map(\.id) == ["1", "2"])
        #expect(steps[1].preview.text == "See you at 3.")
        #expect(steps[1].preview.recipients == ["Maria"])
        #expect(await log.lines.isEmpty)
        #expect(await person.shown.isEmpty)
    }

    @Test func aBadPlanIsRefusedBeforeTheCard() async throws {
        let (runner, _) = try runner(Log(), says: true)
        #expect(await runner.preview([addA, call("2", "test.nope", "{}")]) == .refused(.unknownTool("test.nope")))
    }

    @Test func anApprovedPlanRunsAsShownWithoutAskingAgain() async throws {
        let log = Log()
        let (preview, _) = try runner(log, says: false)
        guard case .ready(let shown) = await preview.preview([addA, sendHi]) else { Issue.record("not ready"); return }

        let askAgain = PretendPerson(says: false)
        let runner = JobRunner(registry: try registry(log), approver: PlanApprover(approved: shown, fallback: askAgain),
                               context: ToolContext(platform: .macOS))
        let result = await runner.run([addA, sendHi])
        #expect(result.outcome == .completed)
        #expect(await log.lines == ["add A", "send See you at 3."])
        #expect(await askAgain.shown.isEmpty)
    }

    @Test func aMessageThatChangedIsStoppedAndAskedAgain() async throws {
        let log = Log()
        let (preview, _) = try runner(log, says: false)
        guard case .ready(let shown) = await preview.preview([addA, sendHi]) else { Issue.record("not ready"); return }

        // The send that actually arrives says something else.
        let changed = call("2", "test.send", #"{"to":["Maria"],"text":"See you at 4."}"#)
        let askAgain = PretendPerson(says: false)
        let runner = JobRunner(registry: try registry(log), approver: PlanApprover(approved: shown, fallback: askAgain),
                               context: ToolContext(platform: .macOS))
        let result = await runner.run([addA, changed])
        #expect(result.outcome == .declined(id: "2"))
        #expect(await askAgain.shown.first?.preview.text == "See you at 4.")
        #expect(await log.lines == ["add A"])
    }

    @Test func anExtraRecipientIsAlsoAChange() async throws {
        let log = Log()
        let (preview, _) = try runner(log, says: false)
        guard case .ready(let shown) = await preview.preview([sendHi]) else { Issue.record("not ready"); return }
        let wider = call("2", "test.send", #"{"to":["Maria","Joe"],"text":"See you at 3."}"#)
        let askAgain = PretendPerson(says: false)
        let runner = JobRunner(registry: try registry(log), approver: PlanApprover(approved: shown, fallback: askAgain),
                               context: ToolContext(platform: .macOS))
        #expect(await runner.run([wider]).outcome == .declined(id: "2"))
        #expect(await log.lines.isEmpty)
    }

    @Test func undoTakesBackThePlansChanges() async throws {
        let log = Log()
        let (preview, _) = try runner(log, says: false)
        let calls = [addA, call("3", "test.add", #"{"name":"B"}"#)]
        guard case .ready(let shown) = await preview.preview(calls) else { Issue.record("not ready"); return }
        let runner = JobRunner(registry: try registry(log), approver: PlanApprover(approved: shown, fallback: PretendPerson(says: false)),
                               context: ToolContext(platform: .macOS))
        _ = await runner.run(calls)
        await runner.undoAll()
        #expect(await log.lines == ["add A", "add B", "undo add B", "undo add A"])
    }
}
