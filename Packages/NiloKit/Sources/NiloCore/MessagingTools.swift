import Foundation

// Messages and WhatsApp. Neither can send silently (a platform rule): each tool opens a message
// with the recipients and text filled in, and the person taps Send there. Both are `.send`, so
// the runner always asks first, showing the exact text and every recipient.

public struct Recipient: Codable, Sendable, Equatable {
    public var name: String
    /// A phone number or email address.
    public var address: String
    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }

    /// "Maria Papadopoulou (+30 690 000 0000)". Shown in full, never shortened.
    public var shown: String { name.isEmpty ? address : "\(name) (\(address))" }
}

/// Opens the apps. AppKit or UIKit in the apps, a pretend opener in tests.
public protocol MessageOpener: Sendable {
    func openMessages(to addresses: [String], text: String) async throws
    /// `phone` is digits only, country code first, as WhatsApp links need.
    func openWhatsApp(phone: String, text: String) async throws
}

public struct Opened: Codable, Sendable {
    public var opened = true
}

public struct MessagesComposeTool: AssistantTool {
    public struct Input: Codable, Sendable {
        public var recipients: [Recipient]
        public var text: String
        public init(recipients: [Recipient], text: String) {
            self.recipients = recipients
            self.text = text
        }
    }

    public static let name = "messages.compose"
    public static let summary = "Opens a new message in Messages with the recipients and text filled in. The person taps Send."
    public static let risk = Risk.send
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let opener: any MessageOpener

    public init(opener: any MessageOpener) {
        self.opener = opener
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        guard !input.recipients.isEmpty,
              input.recipients.allSatisfy({ !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }),
              !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRunError.badArguments(Self.name)
        }
        return ToolPreview(title: "Message in Messages", recipients: input.recipients.map(\.shown), text: input.text)
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Opened {
        try await opener.openMessages(to: input.recipients.map(\.address), text: input.text)
        return Opened()
    }
}

public struct WhatsAppComposeTool: AssistantTool {
    /// WhatsApp links take one person. Telling several people means one step each.
    public struct Input: Codable, Sendable {
        public var recipient: Recipient
        public var text: String
        public init(recipient: Recipient, text: String) {
            self.recipient = recipient
            self.text = text
        }
    }

    public static let name = "whatsapp.compose"
    public static let summary = "Opens a WhatsApp chat with one person, with the text filled in. The person taps Send."
    public static let risk = Risk.send
    public static let platforms: Set<Platform> = [.macOS, .iOS, .iPadOS]

    private let opener: any MessageOpener

    public init(opener: any MessageOpener) {
        self.opener = opener
    }

    private func phone(_ input: Input) throws -> String {
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRunError.badArguments(Self.name)
        }
        guard let digits = PhoneNumber.international(input.recipient.address) else {
            let who = input.recipient.name.isEmpty ? "this" : "\(input.recipient.name)\u{2019}s"
            throw ToolRunError.notAllowed(Self.name, reason: "WhatsApp needs \(who) number with its country code, like +30.")
        }
        return digits
    }

    public func preview(_ input: Input, in context: ToolContext) async throws -> ToolPreview {
        _ = try phone(input)
        return ToolPreview(title: "Message on WhatsApp", recipients: [input.recipient.shown], text: input.text)
    }

    public func run(_ input: Input, in context: ToolContext) async throws -> Opened {
        try await opener.openWhatsApp(phone: try phone(input), text: input.text)
        return Opened()
    }
}

public enum PhoneNumber {
    /// Digits with the country code first ("306900000000"), or nil when the number has no
    /// country code. Nilo never guesses the country.
    public static func international(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let hasPlus = trimmed.hasPrefix("+")
        var digits = trimmed.filter(\.isNumber)
        if hasPlus {
            // already international
        } else if digits.hasPrefix("00") {
            digits.removeFirst(2)
        } else {
            return nil
        }
        // Real numbers are 8 to 15 digits with the country code (E.164).
        guard (8...15).contains(digits.count), !digits.hasPrefix("0") else { return nil }
        return digits
    }
}
