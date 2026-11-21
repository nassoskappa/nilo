import Testing
@testable import NiloCore

@Suite("Approval rules")
struct ApprovalTests {
    let policy = ApprovalPolicy()

    @Test func readsRunAtOnce() {
        #expect(policy.decision(for: .read) == .runNow)
    }

    @Test func changesShowAPreview() {
        #expect(policy.decision(for: .change) == .preview)
    }

    @Test func sendingAndDeletingAlwaysAsk() {
        #expect(policy.decision(for: .send) == .askFirst)
        #expect(policy.decision(for: .delete) == .askFirst)
        #expect(Risk.send.needsExplicitApproval)
        #expect(Risk.delete.needsExplicitApproval)
        #expect(!Risk.change.needsExplicitApproval)
    }
}
