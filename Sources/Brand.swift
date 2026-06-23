import Foundation

/// Single source of truth for Šapat's identity.
///
/// The one place the name, bundle id, GitHub repo slug, and on-disk locations are
/// spelled out — everything else (logging, history storage, the updater's staging
/// cache, the temp recording) derives from here, so a future rename touches one file.
enum Brand {
    /// User-facing name, with the caron. Mirrors `CFBundleDisplayName` in `Info.plist`.
    static let displayName = "Šapat"
    /// ASCII identifier for the bundle, executable, and on-disk folders.
    static let name = "Sapat"
    /// The Cyrillic letter that opens "шапат" (whisper) — menu-bar glyph and icon monogram.
    static let monogram = "Ш"

    /// Reverse-DNS bundle identifier — also the `os.Logger` subsystem.
    static let bundleID = "com.stevanpavlovic.Sapat"
    /// "owner/repo" the GitHub Releases live under (in-app updater + installer script).
    static let repository = "pavstev/Sapat"

    /// `~/Library/Application Support/Sapat`, created on first access.
    static func applicationSupportDirectory() throws -> URL {
        try directory(in: .applicationSupportDirectory)
    }

    /// `~/Library/Caches/Sapat/Updates` — where the updater stages a downloaded build.
    static func updatesCacheDirectory() throws -> URL {
        try directory(in: .cachesDirectory, subpath: "Updates")
    }

    /// Scratch WAV the recorder writes to before transcription.
    static var temporaryRecordingURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.lowercased())-recording.wav")
    }

    private static func directory(in domain: FileManager.SearchPathDirectory, subpath: String? = nil) throws -> URL {
        var url = FileManager.default.urls(for: domain, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
        if let subpath { url.appendPathComponent(subpath, isDirectory: true) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
