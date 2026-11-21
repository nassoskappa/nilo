import Foundation

/// Every tool call passes through here before it runs.
/// The rules live in code, outside any model, so no model can talk past them.
public struct ApprovalPolicy: Sendable {
    public init() {}

    public enum Decision: Sendable, Equatable {
        case runNow
        case preview      // show what changes, offer undo
        case askFirst     // show exact text, recipients or items; wait for a tap
    }

    public func decision(for risk: Risk) -> Decision {
        switch risk {
        case .read: return .runNow
        case .change: return .preview
        case .send, .delete: return .askFirst
        }
    }
}
