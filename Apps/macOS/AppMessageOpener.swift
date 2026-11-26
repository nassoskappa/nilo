import AppKit
import NiloCore

/// Opens Messages or WhatsApp with the message filled in. The person taps Send there:
/// neither app can be sent from silently, and Nilo never tries.
struct AppMessageOpener: MessageOpener {
    struct CouldNotOpen: LocalizedError {
        var app: String
        var errorDescription: String? { "\(app) didn't open." }
    }

    func openMessages(to addresses: [String], text: String) async throws {
        try await MainActor.run {
            guard let service = NSSharingService(named: .composeMessage) else { throw CouldNotOpen(app: "Messages") }
            service.recipients = addresses
            guard service.canPerform(withItems: [text]) else { throw CouldNotOpen(app: "Messages") }
            service.perform(withItems: [text])
        }
    }

    func openWhatsApp(phone: String, text: String) async throws {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)]
        let encoded = query.percentEncodedQuery ?? ""
        try await MainActor.run {
            // The WhatsApp app if it's installed, else WhatsApp in the browser.
            let appURL = URL(string: "whatsapp://send?\(encoded)")
            let webURL = URL(string: "https://api.whatsapp.com/send?\(encoded)")
            let hasApp = appURL.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
            guard let url = hasApp ? appURL : webURL, NSWorkspace.shared.open(url) else {
                throw CouldNotOpen(app: "WhatsApp")
            }
        }
    }
}
