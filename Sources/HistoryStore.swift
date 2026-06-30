import Foundation
import Observation

/// Outcome of a translation job. Old history files predate this field and held only
/// successful translations, so a missing value decodes to `.completed`.
enum RecordStatus: String, Codable {
    case completed
    case failed
}

/// One persisted Serbian→English job — completed or failed. A failed entry keeps a link to
/// its recording (the live WAV we own, or the user's imported file) so the job can be
/// retried straight from History, and so nothing said is ever lost to a transient failure.
struct TranslationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let serbian: String
    let english: String
    let model: String
    let source: TranslationSource
    let status: RecordStatus
    /// Why a failed job failed (user-facing); nil for completed entries.
    let errorMessage: String?
    /// Basename of the durable WAV in `Brand.recordingsDirectory()` for a live capture —
    /// the audio we keep so a failed run can be retried. Nil once pruned or never recorded.
    let audioFileName: String?
    /// Absolute path to the user's own file for an imported recording (we never delete it).
    let importedPath: String?
    /// Display name for an imported recording.
    let importedFileName: String?
    /// Whether the user pinned this entry — sorted to the top. Migration-safe (defaults false).
    var pinned: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        serbian: String,
        english: String,
        model: String,
        source: TranslationSource,
        status: RecordStatus = .completed,
        errorMessage: String? = nil,
        audioFileName: String? = nil,
        importedPath: String? = nil,
        importedFileName: String? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.date = date
        self.serbian = serbian
        self.english = english
        self.model = model
        self.source = source
        self.status = status
        self.errorMessage = errorMessage
        self.audioFileName = audioFileName
        self.importedPath = importedPath
        self.importedFileName = importedFileName
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, serbian, english, model, source
        case status, errorMessage, audioFileName, importedPath, importedFileName, pinned
    }

    /// Tolerant decode: records written before the failure-tracking fields existed carry only
    /// the core translation keys, so the new fields default (status → `.completed`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        serbian = try c.decodeIfPresent(String.self, forKey: .serbian) ?? ""
        english = try c.decodeIfPresent(String.self, forKey: .english) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        source = TranslationSource(persisted: try c.decodeIfPresent(String.self, forKey: .source) ?? "")
        status = try c.decodeIfPresent(RecordStatus.self, forKey: .status) ?? .completed
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        importedPath = try c.decodeIfPresent(String.self, forKey: .importedPath)
        importedFileName = try c.decodeIfPresent(String.self, forKey: .importedFileName)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }

    var isFailed: Bool { status == .failed }

    /// The audio backing this entry, if one was linked. Live captures live in the app's
    /// Recordings folder; imports point at the user's own file. The file may have been
    /// pruned (or moved, for an import) since — check `audioExists` before relying on it.
    var audioURL: URL? {
        if let importedPath { return URL(fileURLWithPath: importedPath) }
        if let audioFileName, let dir = try? Brand.recordingsDirectory() {
            return dir.appendingPathComponent(audioFileName)
        }
        return nil
    }

    /// Whether the recording is still on disk, i.e. whether the job can be retried.
    var audioExists: Bool {
        guard let audioURL else { return false }
        return FileManager.default.fileExists(atPath: audioURL.path)
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
    private let memory: MemoryStore

    /// `url` and `memory` are injectable for tests; production uses the JSON in Application
    /// Support and the shared semantic index.
    init(url: URL? = nil, memory: MemoryStore = .shared) {
        let base = (try? Brand.applicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory
        self.url = url ?? base.appendingPathComponent("history.json")
        self.memory = memory
        load()
        // Seed the semantic index from the durable JSON (idempotent backfill). JSON stays the
        // record of truth — preserving the tolerant decode + failed-entry retry guarantees —
        // while the index powers retrieval and search.
        let snapshot = records.map(Self.indexFields)
        Task { await memory.backfill(snapshot) }
    }

    /// Insert a new record at the top, or replace an existing one in place (matched by `id`).
    /// Retrying a failed job reuses its id, so this updates that entry instead of duplicating
    /// it — a failure that later succeeds simply flips to a completed entry.
    func upsert(_ record: TranslationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            var merged = record
            merged.pinned = records[index].pinned // pin is store-owned ordering state — a re-upsert (e.g. Retry) must not clobber it
            records[index] = merged
        } else {
            records.insert(record, at: 0)
        }
        sortRecords()
        save()
        let fields = Self.indexFields(record)
        let store = memory
        Task { await store.index(
            id: fields.id, date: fields.date, serbian: fields.serbian,
            artifact: fields.artifact, intent: "", mode: fields.mode) }
    }

    func delete(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        // Reclaim the disk for a live capture we own — never the user's imported file.
        if let name = record.audioFileName, let dir = try? Brand.recordingsDirectory() {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        save()
        let id = record.id.uuidString
        let store = memory
        Task { await store.remove(id: id) }
    }

    private static func indexFields(_ r: TranslationRecord) -> (id: String, date: Date, serbian: String, artifact: String, mode: String) {
        (id: r.id.uuidString, date: r.date, serbian: r.serbian, artifact: r.english, mode: r.source.rawValue)
    }

    /// Basenames of recordings that back a *failed* entry — held out of pruning so a retry
    /// stays possible for as long as the failed entry exists.
    var protectedAudioFileNames: Set<String> {
        Set(records.compactMap { $0.isFailed ? $0.audioFileName : nil })
    }

    /// Pin/unpin an entry and re-sort (pinned to the top). Pin is a UI/ordering concept, not a
    /// retrieval signal, so the memory index is untouched.
    func togglePin(_ record: TranslationRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].pinned.toggle()
        sortRecords()
        save()
    }

    /// Pinned entries first, then newest-first within each group.
    private func sortRecords() {
        records.sort { lhs, rhs in lhs.pinned != rhs.pinned ? lhs.pinned : lhs.date > rhs.date }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) else { return }
        records = decoded
        sortRecords()
    }

    private func save() {
        do {
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            Log.recorder.error("History save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
