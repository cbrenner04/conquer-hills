import SwiftUI
import WorkoutKit

/// Prompt settings: how other audio behaves during prompts, and which voice speaks them.
struct SettingsView: View {
    @AppStorage(SpeechAnnouncer.audioModeKey) private var audioMode = PromptAudioMode.default.rawValue
    @AppStorage(SpeechAnnouncer.voiceKey) private var voiceID = ""
    @State private var previewer = SpeechAnnouncer()
    private let voices = SpeechAnnouncer.availableVoices()

    private var mode: PromptAudioMode { PromptAudioMode(rawValue: audioMode) ?? .default }

    var body: some View {
        List {
            Section {
                ForEach(PromptAudioMode.allCases) { option in
                    Button {
                        audioMode = option.rawValue
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer()
                            if option == mode {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("audio-mode-\(option.rawValue)")
                    .accessibilityAddTraits(option == mode ? .isSelected : [])
                }
            } header: {
                Text("Other audio during prompts")
            } footer: {
                Text(mode.explanation)
            }

            Section {
                voiceRow(id: "", name: "System default", detail: nil)
                ForEach(voices) { voice in
                    voiceRow(id: voice.id, name: voice.name, detail: detail(voice))
                }
            } header: {
                Text("Voice")
            } footer: {
                Text(
                    "More natural voices can be downloaded in iOS Settings → Accessibility → Spoken Content → Voices. They appear here once downloaded."
                )
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
        .onDisappear { previewer.stop() }
    }

    private func detail(_ voice: VoiceOption) -> String {
        [voice.language, voice.quality.label].compactMap { $0 }.joined(separator: " · ")
    }

    private func voiceRow(id: String, name: String, detail: String?) -> some View {
        HStack {
            Button {
                voiceID = id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        if let detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if voiceID == id {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .tint(.primary)
            .buttonStyle(.borderless)
            .accessibilityIdentifier(id.isEmpty ? "voice-default" : "voice-\(id)")
            Button {
                previewer.preview(VoiceCatalog.previewText, voiceIdentifier: id)
            } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview \(name)")
        }
    }
}
