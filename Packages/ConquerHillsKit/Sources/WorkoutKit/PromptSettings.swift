/// How other audio (music, podcasts, video) behaves while a prompt is spoken. The app maps each choice to
/// `AVAudioSession` options; this type holds the choice and its wording so it can be stored and tested.
public enum PromptAudioMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Other audio keeps playing, quieter, under the prompt. The default.
    case lower
    /// Music is lowered; podcasts and spoken-word video pause during the prompt and resume after.
    case pauseSpokenAudio
    /// Other audio is left at full volume; the prompt plays on top.
    case fullVolume

    public static let `default` = PromptAudioMode.lower

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lower: "Lower it"
        case .pauseSpokenAudio: "Pause spoken audio"
        case .fullVolume: "Keep it at full volume"
        }
    }

    public var explanation: String {
        switch self {
        case .lower: "Music, podcasts, and video keep playing, quieter, while a prompt is spoken."
        case .pauseSpokenAudio:
            "Music is lowered; podcasts and talk or news video pause during a prompt and resume after."
        case .fullVolume: "Other audio isn't changed; prompts play on top."
        }
    }
}

/// A speech voice as the settings screen lists it, independent of `AVSpeechSynthesisVoice`.
public struct VoiceOption: Identifiable, Equatable, Sendable {
    public enum Quality: Int, Comparable, Sendable {
        case standard, enhanced, premium

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String? {
            switch self {
            case .standard: nil
            case .enhanced: "Enhanced"
            case .premium: "Premium"
            }
        }
    }

    public let id: String
    public let name: String
    /// BCP 47 language, e.g. "en-US".
    public let language: String
    public let quality: Quality

    public init(id: String, name: String, language: String, quality: Quality) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }
}

/// Which voices to offer and which one to use.
public enum VoiceCatalog {
    /// English voices, best quality first, then by name and language.
    public static func options(from voices: [VoiceOption]) -> [VoiceOption] {
        voices
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.language < $1.language
            }
    }

    /// The voice to speak with: the chosen one if it's still on the phone, otherwise nil (the system default).
    public static func resolve(chosen id: String?, available: [VoiceOption]) -> String? {
        guard let id, available.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// What the Preview button says: a real change prompt.
    public static var previewText: String {
        PromptWording.announcement(for: .inclineChange(fromPercent: 3, toPercent: 6.5)).text
    }
}

/// Retries an operation that can fail transiently, such as releasing an audio session while the speech engine is
/// still shutting down.
public enum Retry {
    /// Calls `operation` until it succeeds, up to `attempts` times, waiting `interval` between tries. Returns
    /// whether it eventually succeeded. `onFailure` is told about every failed attempt (for logging). Stops early,
    /// returning false, if the task is cancelled.
    /// Runs on the caller's actor (`isolation`), so the closures never cross into another concurrency domain.
    public static func until(
        isolation: isolated (any Actor)? = #isolation,
        attempts: Int, interval: Duration,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onFailure: (_ attempt: Int, _ error: any Error) -> Void = { _, _ in },
        operation: () throws -> Void
    ) async -> Bool {
        for attempt in 1...max(attempts, 1) {
            if Task.isCancelled { return false }
            do {
                try operation()
                return true
            } catch {
                onFailure(attempt, error)
                if attempt < attempts {
                    do { try await sleep(interval) } catch { return false }
                }
            }
        }
        return false
    }
}
