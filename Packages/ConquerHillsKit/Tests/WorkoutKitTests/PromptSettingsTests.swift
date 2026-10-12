import Testing

@testable import WorkoutKit

@Suite("Prompt settings")
struct PromptSettingsTests {
    @Test("Other audio defaults to Lower it, and every choice stores and explains itself")
    func audioModes() {
        #expect(PromptAudioMode.default == .lower)
        #expect(PromptAudioMode.allCases.map(\.rawValue) == ["lower", "pauseSpokenAudio", "fullVolume"])
        for mode in PromptAudioMode.allCases {
            #expect(PromptAudioMode(rawValue: mode.rawValue) == mode)
            #expect(!mode.title.isEmpty && !mode.explanation.isEmpty)
        }
    }

    private let voices = [
        VoiceOption(id: "fr", name: "Thomas", language: "fr-FR", quality: .premium),
        VoiceOption(id: "samantha", name: "Samantha", language: "en-US", quality: .standard),
        VoiceOption(id: "ava-premium", name: "Ava", language: "en-US", quality: .premium),
        VoiceOption(id: "daniel", name: "Daniel", language: "en-GB", quality: .enhanced),
        VoiceOption(id: "aaron", name: "Aaron", language: "en-US", quality: .standard),
    ]

    @Test("Voices offered are English, best quality first, then by name")
    func voiceOrder() {
        #expect(VoiceCatalog.options(from: voices).map(\.id) == ["ava-premium", "daniel", "aaron", "samantha"])
    }

    @Test("A chosen voice is used while it's on the phone, otherwise the system default")
    func voiceResolution() {
        let options = VoiceCatalog.options(from: voices)

        #expect(VoiceCatalog.resolve(chosen: "daniel", available: options) == "daniel")
        #expect(VoiceCatalog.resolve(chosen: "deleted-voice", available: options) == nil)
        #expect(VoiceCatalog.resolve(chosen: "fr", available: options) == nil)
        #expect(VoiceCatalog.resolve(chosen: nil, available: options) == nil)
    }

    @Test("Preview says a real change prompt")
    func previewText() {
        #expect(VoiceCatalog.previewText == "Now: up to 6.5 percent.")
    }
}

@Suite("Retry")
struct RetryTests {
    private struct Busy: Error {}

    /// Counts calls and fails the first `failures` of them.
    private final class Flaky: @unchecked Sendable {
        var calls = 0
        let failures: Int
        init(failures: Int) { self.failures = failures }

        func run() throws {
            calls += 1
            if calls <= failures { throw Busy() }
        }
    }

    @Test("Succeeds after transient failures, reporting each one")
    func transientFailures() async {
        let flaky = Flaky(failures: 2)
        var reported: [Int] = []

        let succeeded = await Retry.until(
            attempts: 10, interval: .milliseconds(300), sleep: { _ in },
            onFailure: { attempt, _ in reported.append(attempt) }, operation: { try flaky.run() })

        #expect(succeeded)
        #expect(flaky.calls == 3)
        #expect(reported == [1, 2])
    }

    @Test("Gives up after the last attempt")
    func givesUp() async {
        let flaky = Flaky(failures: 100)

        let succeeded = await Retry.until(
            attempts: 4, interval: .milliseconds(300), sleep: { _ in }, operation: { try flaky.run() })

        #expect(!succeeded)
        #expect(flaky.calls == 4)
    }

    @Test("Succeeding first time doesn't wait")
    func noWaitOnSuccess() async {
        let flaky = Flaky(failures: 0)
        let succeeded = await Retry.until(
            attempts: 3, interval: .seconds(60), sleep: { _ in Issue.record("Shouldn't sleep") },
            operation: { try flaky.run() })

        #expect(succeeded)
        #expect(flaky.calls == 1)
    }

    @Test("A cancelled task stops retrying")
    func cancellation() async {
        let flaky = Flaky(failures: 100)
        let task = Task {
            await Retry.until(attempts: 1000, interval: .milliseconds(1), operation: { try flaky.run() })
        }
        task.cancel()

        #expect(await task.value == false)
        #expect(flaky.calls < 1000)
    }
}
