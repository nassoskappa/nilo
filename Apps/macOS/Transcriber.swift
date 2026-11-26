import AVFoundation
import os
import Speech

/// Turns the microphone's sound into words, on the Mac, with Apple's speech recognizer.
/// The audio never leaves the device and nothing is kept.
///
/// The microphone hands every buffer to `sink`. Words arrive through `onText`: `settled` words
/// won't change any more, `pending` words are still being worked out.
@MainActor
final class Transcriber {
    enum Readiness {
        case ready
        /// The recognizer is fetching its language files (first use only).
        case downloading
        /// The Mac's language isn't supported.
        case unsupported
        case failed
    }

    /// Settled words, then words still being worked out.
    var onText: ((_ settled: String, _ pending: String) -> Void)?

    /// Hand this to the microphone. Safe to call from the audio thread.
    nonisolated var sink: @Sendable (AVAudioPCMBuffer) -> Void {
        let feed = self.feed
        return { buffer in feed.push(buffer) }
    }

    private nonisolated let feed = Feed()
    private var locale: Locale?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var results: Task<Void, Never>?
    private var settled = ""
    private var pending = ""
    private static let log = Logger(subsystem: "nilo", category: "voice")

    var isRunning: Bool { analyzer != nil }

    /// Starts a new transcription. `onProgress` reports a download on first use.
    func start(onProgress: @escaping (Readiness) -> Void) async -> Readiness {
        await cancel()
        settled = ""
        pending = ""

        if locale == nil {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        }
        guard let locale else { return .unsupported }

        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: []
        )
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onProgress(.downloading)
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                return .failed
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            try await analyzer.start(inputSequence: stream)
            self.transcriber = transcriber
            self.analyzer = analyzer
            listen(to: transcriber)
            feed.open(continuation: continuation, format: format)
            return .ready
        } catch {
            Self.log.error("Voice could not start: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// The person has finished: settle the last words and return everything heard.
    func finish() async -> String {
        guard let analyzer else { return "" }
        feed.close()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await results?.value
        let text = joinWords(settled, pending)
        reset()
        return text
    }

    /// Stop without waiting for the last words.
    func cancel() async {
        guard let analyzer else { return }
        feed.close()
        await analyzer.cancelAndFinishNow()
        results?.cancel()
        reset()
    }

    private func reset() {
        analyzer = nil
        transcriber = nil
        results = nil
    }

    private func listen(to transcriber: SpeechTranscriber) {
        results = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.settled = joinWords(self.settled, text)
                        self.pending = ""
                    } else {
                        self.pending = text
                    }
                    self.onText?(self.settled, self.pending)
                }
            } catch {
                Self.log.error("Voice stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Converts the microphone's buffers to the recognizer's format and passes them on. Used from
/// the audio thread; a lock guards its state.
private final class Feed: @unchecked Sendable {
    private struct State {
        var continuation: AsyncStream<AnalyzerInput>.Continuation?
        var format: AVAudioFormat?
        var converter: AVAudioConverter?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    func open(continuation: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) {
        state.withLockUnchecked { $0 = State(continuation: continuation, format: format, converter: nil) }
    }

    func close() {
        state.withLockUnchecked { s in
            s.continuation?.finish()
            s = State()
        }
    }

    /// Buffers that arrive before the recognizer is ready, or after it closes, are dropped.
    func push(_ buffer: AVAudioPCMBuffer) {
        state.withLockUnchecked { s in
            guard let continuation = s.continuation, let format = s.format else { return }
            if s.converter == nil || s.converter?.inputFormat != buffer.format {
                s.converter = AVAudioConverter(from: buffer.format, to: format)
            }
            guard let converter = s.converter else { return }
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var given = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if given {
                    status.pointee = .noDataNow
                    return nil
                }
                given = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: out))
        }
    }
}
