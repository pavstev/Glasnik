import SwiftUI

/// Standard preferences window. For v1 the global shortcut is fixed (⌥⌘G); this
/// surfaces it and a little about text. The same info also appears in the popover.
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Global Shortcut") {
                LabeledContent("Record toggle", value: GlasnikShortcut.display)
                Text("Press \(GlasnikShortcut.display) from any app to start or stop recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Glasnik — record Serbian, get polished English. Transcription runs on-device with WhisperKit; a local Ollama model polishes the translation when it's running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}
