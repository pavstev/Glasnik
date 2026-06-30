import AppKit
import CryptoKit
import Foundation
import Observation

/// In-app updater against the GitHub Releases API — no third-party dependency.
///
/// Beyond "detect a newer release", it now installs automatically: it downloads the
/// release `.zip`, verifies it against the published `.zip.sha256`, unzips + strips the
/// Gatekeeper quarantine, atomically swaps the running `.app` in place, and relaunches.
/// This works with the project's ad-hoc signing because the app is **non-sandboxed** and
/// runs as the user — exactly what `scripts/install.sh` relies on. Auto-install is on by
/// default and gated only on the app being idle (never swaps mid-recording).
@MainActor
@Observable
final class UpdateChecker {
    /// "owner/repo" the GitHub Releases live under (see `Brand`).
    static let repository = Brand.repository

    /// UserDefaults key for the auto-update preference. There's no UI for it now (the app is
    /// a single screen); it simply defaults to `true`.
    static let automaticUpdatesKey = "automaticUpdates"

    /// Where the updater is in the check → download → install lifecycle.
    enum Phase: Equatable {
        case idle                            // up to date / nothing pending
        case available(version: String)      // newer release found, not yet downloaded
        case downloading(version: String)    // fetching the zip (indeterminate)
        case readyToInstall(version: String) // verified + staged, awaiting the swap
        case installing(version: String)     // swapping the bundle, about to relaunch
        case failed(String)                  // download/verify/install error
    }

    private(set) var phase: Phase = .idle
    private(set) var isChecking = false
    private(set) var releaseURL: URL?
    /// Surfaced only for manual checks (silent launch checks swallow transient errors).
    private(set) var lastError: String?

    /// True whenever there's update activity worth showing in the popover.
    var updateAvailable: Bool {
        if case .idle = phase { return false }
        return true
    }

    /// The version string attached to the current phase, if any.
    var pendingVersion: String? {
        switch phase {
        case .available(let v), .downloading(let v), .readyToInstall(let v), .installing(let v):
            return v
        case .idle, .failed:
            return nil
        }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Defaults to on when the user hasn't chosen otherwise.
    var automaticUpdates: Bool {
        UserDefaults.standard.object(forKey: Self.automaticUpdatesKey) as? Bool ?? true
    }

    // MARK: Coordination hooks (set by AppDelegate)

    /// Returns `true` when it's safe to swap the bundle — i.e. not recording or busy.
    var canInstallNow: () -> Bool = { true }

    // MARK: Staged download

    private var stagedAppURL: URL?
    private var zipAssetURL: URL?
    private var checksumAssetURL: URL?
    private var signatureAssetURL: URL?

    // MARK: - Check

    /// Queries the latest release. `silent` suppresses surfacing transient errors
    /// (used for the automatic check at launch). When a newer release is found and
    /// automatic updates are on, this kicks off the download immediately.
    func check(silent: Bool = true) async {
        guard !isChecking else { return }
        // Don't disturb an in-flight download/install.
        switch phase {
        case .downloading, .installing: return
        default: break
        }
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            switch http.statusCode {
            case 404:
                return // no releases published yet — nothing to report
            case 200:
                break
            default:
                if !silent { lastError = "GitHub returned HTTP \(http.statusCode)." }
                return
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = Self.normalize(release.tagName)
            releaseURL = URL(string: release.htmlURL)

            guard Self.isVersion(latest, newerThan: Self.normalize(currentVersion)) else {
                // Up to date — clear any stale pending state.
                if case .readyToInstall = phase {} else { phase = .idle }
                return
            }

            zipAssetURL = Self.zipAsset(from: release.assets).flatMap { URL(string: $0.browserDownloadURL) }
            checksumAssetURL = Self.checksumAsset(from: release.assets).flatMap { URL(string: $0.browserDownloadURL) }
            signatureAssetURL = Self.signatureAsset(from: release.assets).flatMap { URL(string: $0.browserDownloadURL) }

            // A release with no detached signature can't be verified, so skip it QUIETLY —
            // absence of a signature is the benign "not signed yet" case (e.g. a release that
            // predates signing), not tampering. We never download or offer an unverifiable
            // build, and never alarm the user. The loud "refused for your safety" state is
            // reserved for a signature that is present but invalid (the real tamper signal).
            guard signatureAssetURL != nil else {
                Log.update.info("Latest release \(latest, privacy: .public) is unsigned — skipping (not verifiable).")
                if case .readyToInstall = phase {} else { phase = .idle }
                return
            }

            // Already staged this version? Leave it ready.
            if case .readyToInstall(let staged) = phase, staged == latest { return }

            if automaticUpdates, zipAssetURL != nil {
                await downloadAndStage(version: latest)
            } else {
                phase = .available(version: latest)
            }
        } catch {
            if !silent { lastError = error.localizedDescription }
        }
    }

    // MARK: - Download + stage

    /// User-tapped "Download" on the `.available` banner.
    func downloadNow() {
        guard let version = pendingVersion else { return }
        Task { await downloadAndStage(version: version) }
    }

    private func downloadAndStage(version: String) async {
        guard let zipURL = zipAssetURL else {
            phase = .failed("This release has no downloadable build yet.")
            return
        }
        phase = .downloading(version: version)
        Log.update.info("Downloading update \(version, privacy: .public)")

        do {
            let cache = try Brand.updatesCacheDirectory()

            // 1. Download the zip to our cache (move out of the per-request tmp at once).
            let (tmpURL, response) = try await URLSession.shared.download(from: zipURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.commandFailed("Download failed (HTTP \(http.statusCode)).")
            }
            let zipDest = cache.appendingPathComponent("update.zip")
            try? FileManager.default.removeItem(at: zipDest)
            try FileManager.default.moveItem(at: tmpURL, to: zipDest)

            // 2. Fetch the published checksum (a cheap corruption pre-check, not the trust anchor).
            var expected: String?
            if let checksumURL = checksumAssetURL {
                if let (cdata, _) = try? await URLSession.shared.data(from: checksumURL) {
                    expected = Self.parseChecksum(String(decoding: cdata, as: UTF8.self))
                }
            }

            // 3. Fetch the detached ed25519 signature — the actual trust anchor (F3).
            var signature: Data?
            if let signatureURL = signatureAssetURL {
                if let (sdata, _) = try? await URLSession.shared.data(from: signatureURL) {
                    signature = ReleaseSignature.parseSignature(sdata)
                }
            }

            // 4. Verify (signature, fail-closed) + unzip off the main actor (blocking file work).
            let staged = try await Task.detached(priority: .utility) {
                try Self.verifyAndUnzip(zipURL: zipDest, signature: signature, expectedSHA256: expected, into: cache)
            }.value

            stagedAppURL = staged
            phase = .readyToInstall(version: version)
            Log.update.info("Update \(version, privacy: .public) staged at \(staged.path, privacy: .public)")

            installIfReady()
        } catch {
            phase = .failed(Self.describe(error))
            Log.update.error("Update download failed: \(self.lastDescribed, privacy: .public)")
        }
    }

    private var lastDescribed: String {
        if case .failed(let m) = phase { return m }
        return ""
    }

    // MARK: - Install

    /// Installs the staged build if everything lines up: a verified download is ready,
    /// automatic updates are on, and the app is idle. Called after staging and whenever
    /// the app returns to idle (so a download that finished mid-recording lands safely).
    func installIfReady() {
        guard automaticUpdates, canInstallNow() else { return }
        guard case .readyToInstall = phase else { return }
        install()
    }

    /// User-tapped "Restart to update".
    func install() {
        guard case .readyToInstall(let version) = phase, let staged = stagedAppURL else { return }
        phase = .installing(version: version)
        let installed = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        Log.update.info("Installing update \(version, privacy: .public)")

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Self.swap(staged: staged, installed: installed)
                }.value
                Self.relaunch(appURL: installed, afterPID: pid)
                NSApp.terminate(nil)
            } catch {
                phase = .failed(Self.describe(error))
                Log.update.error("Update install failed: \(self.lastDescribed, privacy: .public)")
            }
        }
    }

    func openReleasePage() {
        if let releaseURL { NSWorkspace.shared.open(releaseURL) }
    }

    // MARK: - File operations (nonisolated: run off the main actor)

    /// Verifies the downloaded build (signature — fail closed; SHA-256 — cheap pre-check),
    /// unzips it, locates the `.app`, and strips the quarantine xattr so it launches without a
    /// Gatekeeper prompt. Throws (refusing the install) on any verification failure.
    nonisolated private static func verifyAndUnzip(zipURL: URL, signature: Data?, expectedSHA256: String?, into cache: URL) throws -> URL {
        let data = try Data(contentsOf: zipURL)

        // Corruption pre-check (not the trust anchor): if a checksum is published it must match.
        if let expected = expectedSHA256, !expected.isEmpty {
            guard sha256Hex(data).caseInsensitiveCompare(expected) == .orderedSame else {
                throw UpdateError.checksumMismatch
            }
        }

        // Trust anchor: a valid ed25519 signature over these exact bytes against the embedded
        // public key. FAIL CLOSED — a missing or invalid signature aborts the install.
        try ReleaseSignature.gate(data: data, signature: signature)
        Log.update.info("Update signature verified")

        let extractDir = cache.appendingPathComponent("extract", isDirectory: true)
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        let contents = try FileManager.default.contentsOfDirectory(
            at: extractDir, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInZip
        }
        // Non-sandboxed + running as the user, so we may clear quarantine on our download.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Replaces the installed bundle with the staged one via two same-volume renames
    /// (the running process keeps its handles to the old inode, so this is safe live).
    nonisolated private static func swap(staged: URL, installed: URL) throws {
        let fm = FileManager.default
        let parent = installed.deletingLastPathComponent()
        let name = installed.lastPathComponent
        let incoming = parent.appendingPathComponent(".\(name).new-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".\(name).old-\(UUID().uuidString)")

        // Copy onto the target volume first so the final move is an atomic rename.
        try? fm.removeItem(at: incoming)
        try fm.copyItem(at: staged, to: incoming)

        try fm.moveItem(at: installed, to: backup) // move the running app aside
        do {
            try fm.moveItem(at: incoming, to: installed)
        } catch {
            try? fm.moveItem(at: backup, to: installed) // rollback
            try? fm.removeItem(at: incoming)
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// Detached shell that waits for this process to exit, then reopens the app.
    nonisolated private static func relaunch(appURL: URL, afterPID: Int32) {
        let script = "while /bin/kill -0 \(afterPID) 2>/dev/null; do /bin/sleep 0.2; done; "
            + "/bin/sleep 0.3; /usr/bin/open \"\(appURL.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
    }

    nonisolated private static func run(_ launchPath: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw UpdateError.commandFailed("\(launchPath) exited \(process.terminationStatus): \(message)")
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        (error as? UpdateError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Pure helpers (unit-tested)

    nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts the 64-char hex digest from a checksum file, tolerating the common
    /// `shasum`/`sha256sum` layout (`<hex>  <filename>`) or a bare digest.
    nonisolated static func parseChecksum(_ raw: String) -> String? {
        for token in raw.split(whereSeparator: { " \t\r\n".contains($0) }) {
            let candidate = token.lowercased()
            if candidate.count == 64, candidate.allSatisfy(\.isHexDigit) { return candidate }
        }
        return nil
    }

    nonisolated static func zipAsset(from assets: [ReleaseAsset]) -> ReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }

    nonisolated static func checksumAsset(from assets: [ReleaseAsset]) -> ReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".sha256") }
    }

    /// The detached signature asset (`*.sig`) — the trust anchor for the in-app updater.
    nonisolated static func signatureAsset(from assets: [ReleaseAsset]) -> ReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".sig") }
    }

    nonisolated private static func normalize(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    /// Numeric, dot-separated comparison so `1.10.0` > `1.9.0`.
    nonisolated static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = components(lhs), right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    // MARK: - Wire types

    struct ReleaseAsset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [ReleaseAsset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    enum UpdateError: LocalizedError, Equatable {
        case checksumMismatch
        case noAppInZip
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return "The downloaded update failed its checksum and was discarded."
            case .noAppInZip:
                return "The downloaded update didn't contain an app."
            case .commandFailed(let message):
                return message
            }
        }
    }
}
