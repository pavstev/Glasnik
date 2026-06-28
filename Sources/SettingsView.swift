import SwiftUI

/// Standard preferences window: translation tone + glossary, the LM Studio model id,
/// the global shortcut (⌥⇧Space), and a little about text. All persist via @AppStorage
/// using the same keys `TranslationPreferences` reads.
struct SettingsView: View {
    @AppStorage(TranslationPreferences.toneKey) private var toneRaw = Tone.polished.rawValue
    @AppStorage(TranslationPreferences.glossaryKey) private var glossary = ""
    @AppStorage(TranslationPreferences.modelKey) private var model = ""

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
                    Text("One term per line, e.g. “Đorđe = George”. Applied to every refinement.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Section("Local model (LM Studio)") {
                TextField("Model", text: $model, prompt: Text(TranslationPreferences.defaultModel))
                Text("The model Šapat refines with. On launch it starts LM Studio’s server (port 1234) and downloads + loads this model automatically. Leave blank to use \(TranslationPreferences.defaultModel). Requires LM Studio and its `lms` command-line tool.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section("Global Shortcut") {
                LabeledContent("Record toggle", value: SapatShortcut.display)
            }
            Section("About") {
                Text("\(Brand.displayName) — record Serbian, get clean, precise English. On-device transcription with WhisperKit; local refinement with LM Studio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
