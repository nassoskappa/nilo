import Foundation
import Testing
@testable import NiloCore

actor PretendOpener: MessageOpener {
    private(set) var opened: [String] = []
    func openMessages(to addresses: [String], text: String) async throws {
        opened.append("messages \(addresses.joined(separator: ",")): \(text)")
    }
    func openWhatsApp(phone: String, text: String) async throws {
        opened.append("whatsapp \(phone): \(text)")
    }
}

func messagingRunner(_ opener: PretendOpener, says answer: Bool) throws -> (JobRunner, PretendPerson) {
    var r = ToolRegistry()
    try r.register(MessagesComposeTool(opener: opener))
    try r.register(WhatsAppComposeTool(opener: opener))
    let person = PretendPerson(says: answer)
    return (JobRunner(registry: r, approver: person, context: ToolContext(platform: .macOS)), person)
}

func messagesCall(_ id: String, _ input: MessagesComposeTool.Input) -> ToolCall {
    ToolCall(id: id, toolName: MessagesComposeTool.name, argumentsJSON: try! ToolJSON.encoder.encode(input))
}

func whatsAppCall(_ id: String, _ input: WhatsAppComposeTool.Input) -> ToolCall {
    ToolCall(id: id, toolName: WhatsAppComposeTool.name, argumentsJSON: try! ToolJSON.encoder.encode(input))
}

let maria = Recipient(name: "Maria Papadopoulou", address: "+30 690 000 0000")
let joe = Recipient(name: "Joe Bloggs", address: "joe@example.com")

@Suite("Messages and WhatsApp")
struct MessagingToolsTests {
    @Test func nothingOpensWithoutAYes() async throws {
        let opener = PretendOpener()
        let (runner, _) = try messagingRunner(opener, says: false)
        let result = await runner.run([messagesCall("1", .init(recipients: [maria], text: "See you at 3."))])
        #expect(result.outcome == .declined(id: "1"))
        #expect(await opener.opened.isEmpty)
    }

    @Test func theQuestionShowsTheExactTextAndEveryoneItGoesTo() async throws {
        let opener = PretendOpener()
        let (runner, person) = try messagingRunner(opener, says: true)
        _ = await runner.run([messagesCall("1", .init(recipients: [maria, joe], text: "See you at 3.\nBring the deck."))])
        let shown = try #require(await person.shown.first)
        #expect(shown.risk == .send)
        #expect(shown.preview.text == "See you at 3.\nBring the deck.")
        #expect(shown.preview.recipients == ["Maria Papadopoulou (+30 690 000 0000)", "Joe Bloggs (joe@example.com)"])
        #expect(await opener.opened == ["messages +30 690 000 0000,joe@example.com: See you at 3.\nBring the deck."])
    }

    @Test func whatsAppOpensWithDigitsOnly() async throws {
        let opener = PretendOpener()
        let (runner, _) = try messagingRunner(opener, says: true)
        let result = await runner.run([whatsAppCall("1", .init(recipient: maria, text: "Running late."))])
        #expect(result.outcome == .completed)
        #expect(await opener.opened == ["whatsapp 306900000000: Running late."])
    }

    @Test func aNumberWithoutCountryCodeIsRefusedBeforeAnythingRuns() async throws {
        let opener = PretendOpener()
        let (runner, person) = try messagingRunner(opener, says: true)
        let local = Recipient(name: "Maria", address: "690 000 0000")
        let result = await runner.run([whatsAppCall("1", .init(recipient: local, text: "Hi"))])
        guard case .refused(.notAllowed(WhatsAppComposeTool.name, let reason)) = result.outcome else {
            Issue.record("expected a refusal, got \(result.outcome)")
            return
        }
        #expect(reason.contains("country code"))
        #expect(await person.shown.isEmpty)
        #expect(await opener.opened.isEmpty)
    }

    @Test func aMessageNeedsSomeoneAndSomeText() async throws {
        let (runner, _) = try messagingRunner(PretendOpener(), says: true)
        #expect(await runner.run([messagesCall("1", .init(recipients: [], text: "Hi"))]).outcome == .refused(.badArguments(MessagesComposeTool.name)))
        #expect(await runner.run([messagesCall("2", .init(recipients: [maria], text: "  "))]).outcome == .refused(.badArguments(MessagesComposeTool.name)))
    }

    @Test func internationalNumbers() {
        #expect(PhoneNumber.international("+30 690 000 0000") == "306900000000")
        #expect(PhoneNumber.international("+1 (415) 555-0100") == "14155550100")
        #expect(PhoneNumber.international("0030 690 000 0000") == "306900000000")
        #expect(PhoneNumber.international("690 000 0000") == nil)
        #expect(PhoneNumber.international("+30 12") == nil)
    }
}
