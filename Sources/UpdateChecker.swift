import AppKit
import Foundation
import Observation

/// Lightweight in-app update check against the GitHub Releases API — no third-party
/// dependency. It compares the latest published release tag to the running app's
/// version and, when newer, surfaces a one-click link to the release page.
///
/// (We deliberately skip a full auto-installer like Sparkle: the app ships ad-hoc
/// signed, so an in-place binary swap would fight Gatekeeper. "Detect + open the
/// download" is robust and matches how many lightweight tools handle updates.)
@MainActor
@Observable
final class UpdateChecker {
    /// "owner/repo" the releases live under.
    static let repository = "pavstev/Glasnik"

    private(set) var availableVersion: String?
    private(set) var releaseURL: URL?
    private(set) var isChecking = false
    private(set) var lastError: String?

    var updateAvailable: Bool { availableVersion != nil }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Queries the latest release. `silent` suppresses surfacing transient errors
    /// (used for the automatic check at launch).
    func check(silent: Bool = true) async {
        guard !isChecking else { return }
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
            if Self.isVersion(latest, newerThan: Self.normalize(currentVersion)) {
                availableVersion = latest
                releaseURL = URL(string: release.htmlURL)
            } else {
                availableVersion = nil
                releaseURL = nil
            }
        } catch {
            if !silent { lastError = error.localizedDescription }
        }
    }

    func openReleasePage() {
        if let releaseURL {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    // MARK: - Version helpers

    private static func normalize(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    /// Numeric, dot-separated comparison so `1.10.0` > `1.9.0`.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = components(lhs), right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
