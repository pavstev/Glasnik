import XCTest
@testable import Sapat

/// HistoryStore behaviour around pinning + re-upsert, isolated via an injected JSON path and a
/// throwaway MemoryStore (so it never touches the real history / shared index).
@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("histstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeStore() -> HistoryStore {
        HistoryStore(url: tmp.appendingPathComponent("history.json"),
                     memory: MemoryStore(path: tmp.appendingPathComponent("mem.sqlite")))
    }

    private func record(_ english: String, id: UUID = UUID(), date: TimeInterval) -> TranslationRecord {
        TranslationRecord(id: id, date: Date(timeIntervalSince1970: date), serbian: "s",
                          english: english, model: "m", source: .mlx)
    }

    /// Regression: a re-upsert of an existing id (e.g. Retry) must NOT drop the user's pin.
    func testReUpsertPreservesPin() {
        let store = makeStore()
        let original = record("first", date: 1)
        store.upsert(original)
        store.togglePin(original)
        XCTAssertEqual(store.records.first?.pinned, true)

        // Re-upsert the same id (pinned defaults to false, as upsertHistory builds it).
        store.upsert(record("second", id: original.id, date: 1))

        let updated = store.records.first { $0.id == original.id }
        XCTAssertEqual(updated?.english, "second", "the re-upsert updated the content")
        XCTAssertEqual(updated?.pinned, true, "the pin survives a re-upsert (Retry)")
    }

    func testPinnedEntrySortsToTop() {
        let store = makeStore()
        let older = record("older", date: 1)
        store.upsert(older)
        store.upsert(record("newer", date: 2))
        XCTAssertEqual(store.records.first?.english, "newer", "newest-first by default")

        store.togglePin(older)
        XCTAssertEqual(store.records.first?.english, "older", "a pinned entry sorts above newer unpinned ones")
    }
}
