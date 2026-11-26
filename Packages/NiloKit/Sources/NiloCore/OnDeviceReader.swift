import Foundation

/// Whether a reader can be used right now.
public enum ReaderAvailability: Sendable, Equatable {
    case ready
    /// Apple Intelligence is turned off in System Settings.
    case turnedOff
    /// Still downloading or preparing.
    case notReady
    /// This device can't run it.
    case unsupported
}

#if canImport(FoundationModels)
import FoundationModels

/// Reads requests with Apple's on-device model: free, private, on the device. It only fills in
/// the form; dates are worked out in code (see `Understand`).
@available(macOS 26.0, iOS 26.0, *)
public struct OnDeviceReader: RequestReader {
    public init() {}

    public static var availability: ReaderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable: return .unsupported
        }
    }

    static let instructions = """
        You fill in a form from one request to an assistant that can add a meeting or move an existing meeting. \
        Copy words from the request. Never invent anything. Leave a field empty, 0 or false when the request doesn't say it.
        """

    public func read(_ request: String) async throws -> RequestForm {
        let session = LanguageModelSession(instructions: Self.instructions)
        let form = try await session.respond(to: request, generating: Form.self).content
        return RequestForm(
            job: form.job.job,
            title: form.title,
            people: form.people,
            when: form.when,
            meeting: form.meeting,
            minutes: max(0, form.minutes),
            reason: form.reason,
            tellPeople: form.tellPeople
        )
    }

    @Generable
    enum Kind {
        case addMeeting, moveMeeting, other

        var job: RequestForm.Job {
            switch self {
            case .addMeeting: .addMeeting
            case .moveMeeting: .moveMeeting
            case .other: .other
            }
        }
    }

    @Generable
    struct Form {
        @Guide(description: "Which job: addMeeting to put a new meeting in the calendar, moveMeeting to reschedule an existing one, other for anything else.")
        var job: Kind
        @Guide(description: "The new meeting's title only if the request names it (e.g. 'design review'). Empty if not said.")
        var title: String
        @Guide(description: "First names or full names of the other people involved, exactly as written. Not 'me' or 'I'.")
        var people: [String]
        @Guide(description: "When the new meeting is, or when to move it to, copied word for word (e.g. 'Thursday at 3', 'tomorrow'). Empty if not said.")
        var when: String
        @Guide(description: "For moveMeeting only: the words that identify the existing meeting (e.g. 'my 3pm', 'the design review'). Empty otherwise.")
        var meeting: String
        @Guide(description: "The meeting length in minutes if said (an hour is 60), else 0.")
        var minutes: Int
        @Guide(description: "The reason to give people, word for word, if the request gives one. Empty if not.")
        var reason: String
        @Guide(description: "True only if the request asks to tell, message, text or let the others know.")
        var tellPeople: Bool
    }
}
#endif
