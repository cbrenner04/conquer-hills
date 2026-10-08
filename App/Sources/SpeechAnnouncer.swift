import AVFoundation
import WorkoutKit

/// Speaks prompts over whatever else is playing. Music is lowered (podcasts pause) while a prompt is spoken,
/// then restored.
final class SpeechAnnouncer: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ announcements: [Announcement]) {
        guard !announcements.isEmpty else { return }
        activateSession()
        for announcement in announcements {
            synthesizer.speak(AVSpeechUtterance(string: announcement.text))
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            // Speech still plays without the session; other audio just isn't lowered.
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    fileprivate func finishedUtterance() {
        if !synthesizer.isSpeaking {
            deactivateSession()
        }
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedUtterance() }
    }
}
