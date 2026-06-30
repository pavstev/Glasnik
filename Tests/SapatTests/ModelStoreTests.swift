import XCTest
@testable import Sapat

/// The self-managed model cache's integrity + never-redownload guarantees. We exercise the
/// pure helpers and the "skip files that are already valid" path without any network.
final class ModelStoreTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("modelstore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testSHA256MatchesKnownVector() throws {
        let file = tmp.appendingPathComponent("abc.txt")
        try "abc".data(using: .utf8)!.write(to: file)
        XCTAssertEqual(
            ModelStore.sha256(of: file),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testFileSize() throws {
        let file = tmp.appendingPathComponent("five.bin")
        try Data([1, 2, 3, 4, 5]).write(to: file)
        XCTAssertEqual(ModelStore.fileSize(file), 5)
        XCTAssertNil(ModelStore.fileSize(tmp.appendingPathComponent("missing")))
    }

    func testIsValidBySHA() throws {
        let file = tmp.appendingPathComponent("abc.txt")
        try "abc".data(using: .utf8)!.write(to: file)
        let good = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertTrue(ModelStore.isValid(at: file, sha256: good, expectedSize: nil))
        XCTAssertFalse(ModelStore.isValid(at: file, sha256: String(repeating: "0", count: 64), expectedSize: nil))
    }

    func testIsValidBySizeAndExistence() throws {
        let file = tmp.appendingPathComponent("five.bin")
        try Data([1, 2, 3, 4, 5]).write(to: file)
        XCTAssertTrue(ModelStore.isValid(at: file, sha256: nil, expectedSize: 5))
        XCTAssertFalse(ModelStore.isValid(at: file, sha256: nil, expectedSize: 6))
        XCTAssertTrue(ModelStore.isValid(at: file, sha256: nil, expectedSize: nil)) // existence only
        XCTAssertFalse(ModelStore.isValid(at: tmp.appendingPathComponent("nope"), sha256: nil, expectedSize: nil))
    }

    func testInstallSkipsAlreadyValidFiles() async throws {
        // A file already present + matching its digest must NOT be re-downloaded: install
        // succeeds offline (the URL is bogus and would fail if hit).
        let store = ModelStore(root: tmp)
        let model = ModelStore.ManagedModel(id: "demo", files: [
            ModelStore.RemoteFile(
                url: URL(string: "https://example.invalid/never-fetched.bin")!,
                relativePath: "weights.bin",
                sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                expectedSize: nil),
        ])
        // Pre-place the valid file.
        let folder = await store.folder(for: model)
        try "abc".data(using: .utf8)!.write(to: folder.appendingPathComponent("weights.bin"))

        let installed = await store.isInstalled(model)
        XCTAssertTrue(installed)
        let returned = try await store.install(model)
        XCTAssertEqual(returned.lastPathComponent, "demo")
    }

    func testIsInstalledFalseWhenMissing() async {
        let store = ModelStore(root: tmp)
        let model = ModelStore.ManagedModel(id: "absent", files: [
            ModelStore.RemoteFile(
                url: URL(string: "https://example.invalid/x")!, relativePath: "x.bin",
                sha256: nil, expectedSize: 10),
        ])
        let installed = await store.isInstalled(model)
        XCTAssertFalse(installed)
    }
}
