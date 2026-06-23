import SwiftUI

/// Standard preferences window: translation tone + glossary, the global shortcut
/// (⌥⇧Space), and a little about text. Tone/glossary persist via @AppStorage using the
/// same keys TranslationPreferences reads.
struct SettingsView: View {
    @AppStorage(TranslationPreferences.toneKey) private var toneRaw = Tone.polished.rawValue
    @AppStorage(TranslationPreferences.glossaryKey) private var glossary = ""

    var body: some View {
        Form {
            Section("Translation") {
                Picker("Tone", selection: $toneRaw) {
                    ForEach(Tone.allCases) { tone in
                        Text(tone.label).tag(tone.rawValue)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Glossary").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $glossary)
                        .font(.callout)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text("One term per line, e.g. “Đorđe = George”. Applied when Ollama is running.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Section("Global Shortcut") {
                LabeledContent("Record toggle", value: SapatShortcut.display)
            }
            Section("About") {
                Text("\(Brand.displayName) — record Serbian, get polished English. On-device transcription with WhisperKit; optional local Ollama polish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
