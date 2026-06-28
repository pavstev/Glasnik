import Foundation

/// Makes LM Studio mandatory by driving its `lms` CLI: locate the tool, start the local
/// server, and make sure the configured model is downloaded and loaded. This is what lets
/// the app rely on LM Studio for every refinement instead of silently degrading — when it
/// genuinely can't be made ready, `ensureReady` throws and the caller shows an actionable
/// error (it never falls back to the inferior Whisper translation).
struct LMStudioManager {
    /// Progress steps worth surfacing to the user — the slow ones download/load a model.
    enum Phase: Equatable {
        case startingServer
        case downloadingModel
        case loadingModel

        var message: String {
            switch self {
            case .startingServer: return "Starting LM Studio…"
            case .downloadingModel: return "Downloading refinement model (~5 GB)…"
            case .loadingModel: return "Loading refinement model…"
            }
        }
    }

    /// Context window to request when we load the model ourselves — generous headroom so
    /// most recordings refine in a single pass. (The client still chunks if a transcript
    /// exceeds whatever is actually loaded, e.g. a smaller manual load.)
    var preferredContextLength = 8192
    /// Auto-unload the model after this long idle, so we don't hold ~6 GB forever.
    var modelIdleTTLSeconds = 3600

    /// Locates the `lms` CLI. A Finder-launched app inherits a minimal PATH that excludes
    /// `~/.lmstudio/bin` (where the installer puts it), so we probe explicit locations
    /// rather than trusting `$PATH`.
    static func locateCLI(
        home: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let candidates = [
            "\(home)/.lmstudio/bin/lms",
            "\(home)/.cache/lm-studio/bin/lms",
            "/opt/homebrew/bin/lms",
            "/usr/local/bin/lms",
        ]
        return candidates.first(where: isExecutable)
    }

    /// Ensures `modelKey` is loaded and serving: starts the server if needed, downloads the
    /// model if absent, then loads it. Idempotent and cheap when already loaded.
    func ensureReady(
        modelKey: String,
        client: LMStudioClient,
        onPhase: @escaping @Sendable (Phase) -> Void
    ) async throws {
        // Fast path: already loaded and serving.
        if await client.presence(of: modelKey) == .loaded { return }

        guard let cli = Self.locateCLI() else { throw LMStudioError.cliNotFound }

        if await client.isServerReachable() == false {
            onPhase(.startingServer)
            try await Self.run(cli, ["server", "start"], timeout: 30)
            await Self.waitUntil(timeout: 20) { await client.isServerReachable() }
        }

        switch await client.presence(of: modelKey) {
        case .loaded:
            return
        case .absent, .serverUnreachable:
            onPhase(.downloadingModel)
            try await Self.run(cli, ["get", modelKey, "--mlx", "-y"], timeout: 3600)
            onPhase(.loadingModel)
            try await load(cli: cli, modelKey: modelKey)
        case .downloadedNotLoaded:
            onPhase(.loadingModel)
            try await load(cli: cli, modelKey: modelKey)
        }

        await Self.waitUntil(timeout: 60) { await client.presence(of: modelKey) == .loaded }
        guard await client.presence(of: modelKey) == .loaded else {
            throw LMStudioError.setupFailed("LM Studio couldn't load \(modelKey). Open LM Studio and load it manually.")
        }
    }

    private func load(cli: String, modelKey: String) async throws {
        try await Self.run(cli, [
            "load", modelKey, "-y",
            "--context-length", String(preferredContextLength),
            "--ttl", String(modelIdleTTLSeconds),
        ], timeout: 600)
    }

    // MARK: - Process plumbing (nonisolated: runs off the main actor)

    /// Runs `lms` and waits for it, polling so the call stays cancellable and can time out.
    /// stdout+stderr go to a temp file (not a pipe) so a chatty long download can't deadlock
    /// on a full pipe buffer; the file is read back only to explain a failure.
    nonisolated private static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        // Augment PATH so the CLI's bundled runtime resolves under a Finder-minimal env.
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = env["PATH"].map { "\($0):\(extra)" } ?? extra
        process.environment = env

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapat-lms-\(args.first ?? "cmd")-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle
        defer { try? FileManager.default.removeItem(at: logURL) }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit() // reap the child before returning
                throw CancellationError()
            }
            if Date() > deadline {
                process.terminate()
                process.waitUntilExit()
                throw LMStudioError.setupFailed("lms \(args.first ?? "command") timed out.")
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        try? handle.close()

        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LMStudioError.setupFailed(
                "lms \(args.first ?? "command") failed" + (detail.isEmpty ? " (exit \(process.terminationStatus))." : ": \(detail)")
            )
        }
    }

    /// Polls `condition` until it's true or the timeout elapses (best effort, no throw).
    nonisolated private static func waitUntil(timeout: TimeInterval, _ condition: @Sendable () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
