import AVFoundation
import WorkoutKit
import os

/// Speaks prompts over whatever else is playing, then gives the audio back.
///
/// How other audio behaves while a prompt plays is the runner's choice (`PromptAudioMode`, Settings). The audio
/// session is held only while prompts are queued. Releasing it can fail while the speech engine is still shutting
/// down (iOS reports the session as busy), so the release is retried until it succeeds; otherwise iOS would keep
/// other apps lowered or paused. Launching with `-silentSpeech` (as the UI walkthrough does) turns speech off.
final class SpeechAnnouncer: NSObject {
    static let audioModeKey = "promptAudioMode"
    /// The chosen voice's identifier; empty means the system default.
    static let voiceKey = "promptVoiceIdentifier"

    private static let logger = Logger(subsystem: "com.hills-app.conquerhills", category: "Speech")

    private let isSilent = ProcessInfo.processInfo.arguments.contains("-silentSpeech")
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive = false
    /// Utterances handed to the synthesizer and not yet finished or cancelled.
    private var pendingUtterances = 0
    private var releaseTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ announcements: [Announcement]) {
        speak(announcements.map(\.text), voiceIdentifier: nil)
    }

    /// Speaks one line straight away in a given voice (nil for the saved choice), for Settings' Preview.
    func preview(_ text: String, voiceIdentifier: String?) {
        synthesizer.stopSpeaking(at: .immediate)
        speak([text], voiceIdentifier: voiceIdentifier)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
        releaseSession()
    }

    private func speak(_ texts: [String], voiceIdentifier: String?) {
        guard !texts.isEmpty, !isSilent else { return }
        // A release still being retried would hand the audio back mid-prompt; keep holding it instead.
        releaseTask?.cancel()
        releaseTask = nil
        activateSession()
        let voice = Self.voice(for: voiceIdentifier ?? UserDefaults.standard.string(forKey: Self.voiceKey))
        for text in texts {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            pendingUtterances += 1
            synthesizer.speak(utterance)
        }
    }

    // MARK: Audio session

    /// iOS options for each choice of how other audio behaves during prompts.
    static func options(for mode: PromptAudioMode) -> AVAudioSession.CategoryOptions {
        switch mode {
        case .lower: [.duckOthers]
        case .pauseSpokenAudio: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        case .fullVolume: [.mixWithOthers]
        }
    }

    private func activateSession() {
        guard !sessionActive else { return }
        let mode = UserDefaults.standard.string(forKey: Self.audioModeKey).flatMap(PromptAudioMode.init) ?? .default
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: Self.options(for: mode))
            try session.setActive(true)
            sessionActive = true
        } catch {
            // Speech still plays without the session; other audio just isn't adjusted.
            Self.logger.error("Couldn't activate the audio session: \(error, privacy: .public)")
        }
    }

    /// Gives the audio back to other apps, retrying while iOS reports the session as busy.
    private func releaseSession() {
        guard sessionActive, releaseTask == nil else { return }
        releaseTask = Task { [weak self] in
            let released = await Retry.until(
                attempts: 10, interval: .milliseconds(300),
                onFailure: { attempt, error in
                    Self.logger.error(
                        "Couldn't release the audio session (attempt \(attempt)): \(error, privacy: .public)")
                },
                operation: {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                })
            guard let self, !Task.isCancelled else { return }
            if released {
                sessionActive = false
            } else {
                Self.logger.fault("Gave up releasing the audio session; other apps may stay lowered.")
            }
            releaseTask = nil
        }
    }

    fileprivate func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0 {
            releaseSession()
        }
    }

    // MARK: Voices

    /// The phone's voices as Settings lists them: English, not novelty voices, best quality first.
    static func availableVoices() -> [VoiceOption] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .map { voice in
                let quality: VoiceOption.Quality =
                    switch voice.quality {
                    case .premium: .premium
                    case .enhanced: .enhanced
                    default: .standard
                    }
                return VoiceOption(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
            }
        return VoiceCatalog.options(from: voices)
    }

    /// The voice to use for an identifier, or nil (the system default) if it's empty or no longer on the phone.
    private static func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        let id = identifier.flatMap { $0.isEmpty ? nil : $0 }
        return VoiceCatalog.resolve(chosen: id, available: availableVoices()).flatMap(AVSpeechSynthesisVoice.init)
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
