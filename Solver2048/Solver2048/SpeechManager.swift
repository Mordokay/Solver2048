import AVFoundation
import Combine

/// Manages text-to-speech for announcing solver directions.
/// Listens for Darwin notifications from the broadcast extension and speaks the direction aloud.
@Observable
@MainActor
final class SpeechManager {
    private let synthesizer = AVSpeechSynthesizer()
    private var pollingTimer: Timer?
    private var lastTimestamp: Double = 0

    private(set) var lastSpokenDirection: String = ""
    private(set) var isListening: Bool = false
    private(set) var isExtensionActive: Bool = false

    // MARK: - Audio Session

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback allows background audio; .duckOthers lowers game volume during speech
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("[SpeechManager] Audio session error: \(error)")
        }
    }

    // MARK: - Speech

    func speak(_ direction: String) {
        lastSpokenDirection = direction
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: direction)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    // MARK: - Listening Lifecycle

    func startListening() {
        guard !isListening else { return }
        isListening = true
        setupAudioSession()

        // Listen for Darwin notifications from the extension
        SharedState.observeDarwinNotification { [weak self] in
            Task { @MainActor in
                self?.checkForNewDirection()
                self?.isExtensionActive = SharedState.isExtensionActive
            }
        }

        // Fallback polling timer (Darwin notifications can occasionally be missed)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForNewDirection()
                self?.isExtensionActive = SharedState.isExtensionActive
            }
        }
    }

    func stopListening() {
        isListening = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        SharedState.stopObservingDarwinNotification()
    }

    // MARK: - Direction Check

    private func checkForNewDirection() {
        guard let (direction, timestamp) = SharedState.readDirection() else { return }

        // Only speak if this is a new direction (newer timestamp)
        if timestamp > lastTimestamp {
            lastTimestamp = timestamp
            speak(direction)
        }
    }

}
