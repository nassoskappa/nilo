import AVFoundation
import NiloCore

/// Listens to the microphone and reports only how loud it is. Nothing is recorded or kept:
/// each buffer is measured and thrown away.
///
/// On only while Nilo is listening, so the orange dot in the menu bar means exactly that.
@MainActor
final class Microphone {
    enum Start {
        case listening
        /// The person said no, now or before.
        case denied
        /// No input device, or it would not start.
        case unavailable
    }

    /// Smoothed level 0...1, about 45 times a second while on.
    var onLevel: ((Double) -> Void)?
    /// Called once when the person has finished speaking.
    var onFinished: (() -> Void)?

    private var engine: AVAudioEngine?
    private var activity = VoiceActivity()

    var isOn: Bool { engine != nil }

    /// Asks for permission the first time, then starts. Safe to call when already on.
    func start() async -> Start {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else { return .denied }
        default:
            return .denied
        }
        return begin() ? .listening : .unavailable
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        onLevel?(0)
    }

    private func begin() -> Bool {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        activity = VoiceActivity()
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.measure { [weak self] rms in
            Task { @MainActor in self?.receive(rms) }
        })
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        self.engine = engine
        return true
    }

    private func receive(_ rms: Float) {
        guard isOn else { return }  // a late buffer after stop
        let ended = activity.add(rms: Double(rms), at: ProcessInfo.processInfo.systemUptime)
        onLevel?(activity.level)
        if ended { onFinished?() }
    }

    /// Runs on the audio thread, so it is built outside the main actor. Measures one buffer.
    nonisolated private static func measure(_ deliver: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            deliver((sum / Float(count)).squareRoot())
        }
    }
}
