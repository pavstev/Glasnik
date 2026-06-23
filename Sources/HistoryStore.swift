import Foundation
import Observation

/// One persisted Serbian→English translation.
struct TranslationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let serbian: String
    let english: String
    let model: String
    let source: String // "Ollama" or "Whisper"

    init(id: UUID = UUID(), date: Date, serbian: String, english: String, model: String, source: String) {
        self.id = id
        self.date = date
        self.serbian = serbian
        self.english = english
        self.model = model
        self.source = source
    }
}

/// Observable history store backed by a JSON file in Application Support. (We avoid
/// SwiftData: its @Model/@Query macros need Xcode's macro plugin and so won't build
/// under the Command Line Tools, same as KeyboardShortcuts' #Preview.)
@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [TranslationRecord] = []

    private let url: URL

    init() {
        let base = (try? Brand.applicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("history.json")
        load()
    }

    func add(serbian: String, english: String, model: String, source: String) {
        records.insert(
            TranslationRecord(date: .now, serbian: serbian, english: english, model: model, source: source),
            at: 0
        )
        save()
    }

    func delete(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) else { return }
        records = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        do {
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            Log.recorder.error("History save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
