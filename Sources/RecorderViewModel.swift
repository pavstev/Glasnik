import AppKit
import AVFoundation
import Foundation
import Observation

/// Owns all app state and logic. Created once by `AppDelegate` and injected into the
/// SwiftUI popover via the environment, so recording can be driven by the global
/// hotkey even while the popover is closed.
@MainActor
@Observable
final class RecorderViewModel {
    // MARK: Configuration
    // large-v3: the most accurate multilingual model — best for Serbian. Slower per
    // clip than turbo, but the bake-off showed ~3x fewer word errors.
    private let whisperModel = "openai_whisper-large-v3"
    private let sourceLanguage = "sr" // Serbian

    // Recording format: 16 kHz mono 16-bit PCM WAV — exactly what WhisperKit wants.
    private static let sampleRate = 16_000.0
    private static let channelCount = 1
    private static let bitDepth = 16
    /// Below this, a "recording" is a stray tap, not speech.
    private static let minRecordingSeconds: TimeInterval = 0.3

    // MARK: Observed state (read by the view)
    private(set) var state: AppState = .preparing(progress: nil)
    private(set) var level: Double = 0 // mic level 0...1, drives the record-button pulse
    private(set) var levelHistory: [Double] = [] // recent levels for the menu-bar waveform
    private(set) var recordingDuration: TimeInterval = 0 // elapsed seconds, shown while recording
    private(set) var serbianText = ""
    private(set) var outputText = ""
    /// Live, RAW partial output streamed from the engine while `.translating`; the committed,
    /// sanitized `outputText` replaces it on completion. Empty unless a stream is in flight.
    private(set) var streamingText = ""
    /// Column title for the produced artifact in the result card (varies by Output Mode).
    private(set) var resultTitle: String = OutputModes.default.resultTitle
    /// The pipeline stage currently running — drives the live stage strip; nil when idle.
    private(set) var liveStage: PipelineStage?
    /// The stages the active mode will run, for the strip.
    private(set) var plannedStages: [PipelineStage] = []
    /// The mode that produced the displayed result (rendering uses this, not the live picker).
    private(set) var resultMode: OutputMode = OutputModes.default
    /// How many past notes informed the result (for the "informed by N notes" affordance).
    private(set) var resultRetrievedCount = 0
    private(set) var translationSource: TranslationSource?
    private(set) var notice: String? // transient info, e.g. "No speech detected"
    /// Non-nil while LM Studio is being made ready (server start / model download / load).
    private(set) var engineStatus: String?
    /// Sub-status during processing: elapsed transcription time, or "Refining N of M sections…".
    private(set) var processingDetail: String?
    /// File name when processing an imported recording (nil for live mic recordings).
    private(set) var importedFileName: String?
    private(set) var showCopiedConfirmation = false

    /// Called on every state change so AppKit (the status-bar icon) can react.
    var onStateChange: ((AppState) -> Void)?

    /// Set by AppDelegate so the popover's close (✕) button can dismiss it.
    var onRequestClose: (() -> Void)?

    /// Fires on each metering tick with the recent level buffer (drives the menu-bar waveform).
    var onLevelChange: (([Double]) -> Void)?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
        case .preparing, .transcribing, .translating: return true
        default: return false
        }
    }

    /// Whether the record button should accept a tap right now.
    var canRecord: Bool {
        switch state {
        case .idle, .done, .recording: return true
        default: return false
        }
    }

    /// Whether Import should accept a file right now — same idea as `canRecord`, but never
    /// while a recording is actually in progress.
    var canImport: Bool {
        switch state {
        case .idle, .done: return true
        default: return false
        }
    }

    // MARK: Dependencies
    private let whisper = WhisperEngine()
    /// The active inference backend. The interim default is LM Studio; the in-process MLX
    /// engine becomes the default once the build moves to `xcodebuild`. Swapping this never
    /// touches a caller — refinement goes through the `Inference` protocol and `Refiner`, so
    /// the orchestrator no longer hard-depends on LM Studio (F1).
    private let inference: any Inference = RecorderViewModel.makeInference()
    @ObservationIgnored private lazy var pipeline = ThoughtPipeline(inference: inference, memory: .shared)

    /// Selects the default backend: in-process MLX when its package is present (the shippable
    /// build via xcodebuild), otherwise the LM Studio backend (the CLT fallback + opt-in). The
    /// rest of the app is engine-agnostic, so this is the only place the default is chosen.
    private static func makeInference() -> any Inference {
        #if canImport(MLXLLM)
        return MLXInference()
        #else
        return LMStudioInference()
        #endif
    }
    /// Coalesces concurrent readiness work (the launch warm-up and a refine) so we never run
    /// two model downloads/loads at once.
    private var readinessTask: Task<Void, Error>?

    /// Translation history store; set by AppDelegate.
    var history: HistoryStore?

    // MARK: Recording internals
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
    private var processingTimer: Timer?
    private var processingElapsed = 0 // seconds, drives the elapsed clock in the detail line
    private var transcriptionFraction = 0.0 // WhisperKit's live progress, for the % + estimate

    /// The audio behind the current job, kept so a failed run can be retried without
    /// re-recording. A live recording is durably saved (and deleted on success); an import
    /// points at the user's own file.
    private enum PendingSource {
        case recording(URL) // our durable WAV — clean up on success
        case imported(URL)  // the user's file — never delete
    }
    private var pending: PendingSource?
    /// The history entry for the in-flight job. Held so a failure is recorded and a later
    /// success (via Retry) updates the same entry instead of adding a duplicate. The date is
    /// the original capture time, preserved across retries.
    private var currentRecordID: UUID?
    private var currentRecordDate: Date?
    private var copiedTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Run once at launch: request the microphone and prewarm the Whisper model.
    func prepare() async {
        setState(.preparing(progress: nil))

        let granted = await requestMicrophoneAccess()
        guard granted else {
            setState(.error(AppError(
                message: "Microphone access denied. Šapat needs the microphone to hear you.",
                action: RecoveryAction(label: "Open Microphone Settings", kind: .openMicrophoneSettings)
            )))
            return
        }

        do {
            try await whisper.load(model: whisperModel) { [weak self] fraction in
                Task { @MainActor in self?.setPreparingProgress(fraction) }
            }
            setState(.idle)
            warmUpInference()
            pruneOldRecordings(keeping: 30)
        } catch {
            setState(.error(AppError(
                message: "Couldn't load the speech model. \(error.localizedDescription)",
                action: nil
            )))
        }
    }

    /// Best-effort, non-blocking: at launch we get the inference engine fully ready (model
    /// loaded / server up) so the first refinement is instant. Failures here are silent — the
    /// refine path runs the same readiness check and surfaces a real error only if a recording
    /// actually needs the engine and it still can't be made ready.
    private func warmUpInference() {
        Task { [weak self] in
            do {
                try await self?.ensureInferenceReady()
            } catch {
                Log.llm.info("Inference warm-up deferred: \(error.localizedDescription, privacy: .public)")
                self?.setEngineStatus(nil)
            }
        }
    }

    /// Lightweight progress update during the first-run model download. Skips the
    /// status-bar/log churn of `setState` since it can fire many times a second.
    private func setPreparingProgress(_ fraction: Double) {
        guard case .preparing = state else { return }
        state = .preparing(progress: fraction)
    }

    // MARK: Intent

    /// Start recording if idle/done, stop-and-process if recording. Ignored while busy.
    func toggleRecording() {
        switch state {
        case .recording:
            stopAndProcess()
        case .idle, .done:
            startRecording()
        default:
            break
        }
    }

    /// Transcribe + refine an existing audio or video file (picked or dropped). No length
    /// limit — long files just take longer, and silence is skipped by the same VAD path as
    /// a live recording. Video has its audio track extracted first.
    func importRecording(from url: URL) {
        guard canImport else { return }
        clearResults()
        importedFileName = url.lastPathComponent
        pending = .imported(url)
        setState(.transcribing)
        processingDetail = "Preparing \(url.lastPathComponent)…"
        Task { await runImport(url: url) }
    }

    private func runImport(url: URL) async {
        let prepared: AudioImporter.Prepared
        do {
            prepared = try await AudioImporter.prepare(url)
        } catch {
            importedFileName = nil
            processingDetail = nil
            let message = "Couldn't read “\(url.lastPathComponent)”. \(error.localizedDescription)"
            upsertHistory(serbian: "", english: "", status: .failed, error: message)
            setState(.error(AppError(message: message, action: nil)))
            return
        }
        await transcribeAndRefine(audioPath: prepared.url.path)
        AudioImporter.cleanUp(prepared)
    }

    /// Discards an in-progress recording without transcribing it (Esc / Cancel button).
    func cancelRecording() {
        guard case .recording = state else { return }
        stopMetering()
        recorder?.stop()
        recorder = nil
        level = 0
        levelHistory = []
        recordingDuration = 0
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        clearResults()
        setState(.idle)
        flashNotice("Recording canceled")
    }

    /// "Retry" after an error, cheapest viable path first: re-refine an existing transcript
    /// (LM Studio hiccup), else re-transcribe from the saved audio (transcription failed),
    /// else re-run launch preparation.
    func retryAfterError() {
        if !serbianText.isEmpty {
            Task { await refine() }
            return
        }
        switch pending {
        case .recording(let url) where FileManager.default.fileExists(atPath: url.path):
            Task { await transcribeAndRefine(audioPath: url.path) }
        case .imported(let url):
            importedFileName = url.lastPathComponent
            setState(.transcribing)
            Task { await runImport(url: url) }
        default:
            Task { await prepare() }
        }
    }

    /// Retry a job straight from History, re-running from its kept recording — the reason a
    /// failed entry holds onto its audio. Reuses the entry's id/date so the History row flips
    /// in place (failed → done) rather than spawning a duplicate. No-op while busy/recording.
    func retryFromHistory(_ record: TranslationRecord) {
        guard !isBusy, !isRecording else { return }
        guard let url = record.audioURL, FileManager.default.fileExists(atPath: url.path) else {
            flashNotice("That recording is no longer available to retry")
            return
        }
        clearResults() // resets currentRecordID/date — re-set them below to update the same entry
        currentRecordID = record.id
        currentRecordDate = record.date
        if record.importedPath != nil {
            importedFileName = record.importedFileName ?? url.lastPathComponent
            pending = .imported(url)
            setState(.transcribing)
            processingDetail = "Preparing \(url.lastPathComponent)…"
            Task { await runImport(url: url) }
        } else {
            pending = .recording(url)
            Task { await transcribeAndRefine(audioPath: url.path) }
        }
    }

    /// Called by AppDelegate when the global hotkey couldn't be registered.
    func noteHotkeyUnavailable() {
        flashNotice("Couldn't register \(SapatShortcut.display) — another app may be using it.")
    }

    func performRecoveryAction(_ action: RecoveryAction) {
        switch action.kind {
        case .openMicrophoneSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .openLMStudio:
            let appURL = URL(fileURLWithPath: "/Applications/LM Studio.app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.open(appURL)
            } else if let site = URL(string: "https://lmstudio.ai") {
                NSWorkspace.shared.open(site)
            }
        case .copyCommand(let command):
            copyToPasteboard(command)
        }
    }

    /// Copies the current English translation to the clipboard (explicit Copy button).
    func copyOutput() {
        guard !outputText.isEmpty else { return }
        copyToPasteboard(outputText)
        flashCopied()
    }

    // MARK: Recording

    private func startRecording() {
        clearResults()

        // Save to a durable, uniquely-named file so the recording survives a failed
        // transcription/refinement and can be retried (deleted once it succeeds).
        let url = Self.newRecordingURL()
        try? FileManager.default.removeItem(at: url)

        // AVAudioRecorder converts from the hardware format to our target format internally.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: Self.channelCount,
            AVLinearPCMBitDepthKey: Self.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                setState(.error(AppError(message: "Couldn't start recording.", action: nil)))
                return
            }
            self.recorder = recorder
            recordingURL = url
            recordingDuration = 0
            setState(.recording)
            startMetering()
        } catch {
            setState(.error(AppError(
                message: "Couldn't start recording. \(error.localizedDescription)",
                action: nil
            )))
        }
    }

    private func stopAndProcess() {
        stopMetering()
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        level = 0
        levelHistory = []
        recordingDuration = 0

        guard let url = recordingURL, duration > Self.minRecordingSeconds else {
            if let url = recordingURL { try? FileManager.default.removeItem(at: url) } // nothing worth keeping
            recordingURL = nil
            flashNotice("No speech detected — try again")
            setState(.idle)
            return
        }
        pending = .recording(url)
        Task { await transcribeAndRefine(audioPath: url.path) }
    }

    private func transcribeAndRefine(audioPath: String) async {
        setState(.transcribing)
        startProcessingTimer()
        let serbian: String
        do {
            serbian = try await whisper.run(audioPath: audioPath, task: .transcribe, language: sourceLanguage)
        } catch {
            stopProcessingTimer()
            processingDetail = nil
            let message = "Transcription failed. \(error.localizedDescription)"
            // Record the failure with its recording kept, so it can be retried from History.
            upsertHistory(serbian: "", english: "", status: .failed, error: message)
            setState(.error(AppError(message: message, action: nil)))
            return
        }
        stopProcessingTimer()
        guard isMeaningful(serbian) else {
            processingDetail = nil
            flashNotice("No speech detected — try again")
            setState(.idle)
            return
        }
        serbianText = serbian
        await refine()
    }

    /// Refines the current `serbianText` into English with LM Studio — the only path now
    /// (no Whisper fallback). LM Studio is made ready first; on failure the transcript
    /// stays on screen and the error offers Retry + Open LM Studio, so nothing the speaker
    /// said is lost.
    private func refine() async {
        guard !serbianText.isEmpty else { return }
        let mode = TranslationPreferences.outputMode
        resultTitle = mode.resultTitle
        resultMode = mode
        plannedStages = mode.plannedStages
        liveStage = nil
        resultRetrievedCount = 0
        setState(.translating)
        processingDetail = nil
        streamingText = ""
        do {
            try await ensureInferenceReady()
            // Deltas arrive single-producer + in order from the pipeline, but a per-token
            // `Task { @MainActor … }` would NOT preserve that order (main-actor jobs aren't FIFO
            // by creation). Funnel them through one AsyncStream drained by a single sequential
            // main-actor consumer, so tokens append exactly as produced.
            let (deltas, deltaCont) = AsyncStream<String>.makeStream()
            let drain = Task { @MainActor [weak self] in
                for await delta in deltas { self?.appendStreamDelta(delta) }
            }
            do {
                let result = try await pipeline.run(
                    transcript: serbianText,
                    mode: mode,
                    glossary: TranslationPreferences.glossary,
                    onProgress: { [weak self] detail in
                        Task { @MainActor in self?.processingDetail = detail }
                    },
                    onStage: { [weak self] progress in
                        Task { @MainActor in self?.applyStage(progress) }
                    },
                    onDelta: { deltaCont.yield($0) }
                )
                deltaCont.finish()
                await drain.value // let every buffered delta land before we commit the result
                finish(english: result.primary)
            } catch {
                deltaCont.finish()
                await drain.value
                throw error
            }
        } catch is CancellationError {
            setEngineStatus(nil)
            processingDetail = nil
            setState(.idle)
        } catch {
            setEngineStatus(nil)
            processingDetail = nil
            let appError = inferenceError(for: error)
            // Keep the transcript + recording in History so the refine can be retried.
            upsertHistory(serbian: serbianText, english: "", status: .failed, error: appError.message)
            setState(.error(appError))
        }
    }

    /// Ensures the server is up and the configured model is loaded, coalescing a concurrent
    /// launch warm-up so two `lms` downloads/loads never run at once. The off-main readiness
    /// work reports progress through an `AsyncStream` (it can't touch main-actor state
    /// directly), which we drain here to update `engineStatus`.
    private func ensureInferenceReady() async throws {
        if let existing = readinessTask {
            try await existing.value
            return
        }
        // Coalesce concurrent callers (the launch warm-up + a refine) onto one readiness run so
        // two model downloads/loads never run at once. The task inherits this main actor, so the
        // progress callback can update state directly; the backend throttles it.
        let task = Task { try await self.performReadiness() }
        readinessTask = task
        defer { readinessTask = nil }
        try await task.value // re-throws any setup failure to the caller
    }

    private func performReadiness() async throws {
        defer { setEngineStatus(nil) }
        try await inference.prepare { [weak self] status in
            Task { @MainActor in self?.setEngineStatus(status) }
        }
    }

    private func finish(english: String) {
        let cleaned = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            setState(.error(AppError(message: "The translation came back empty.", action: nil)))
            return
        }
        outputText = cleaned
        translationSource = inference.source
        processingDetail = nil
        streamingText = "" // the committed, sanitized outputText now replaces the live partial
        liveStage = nil
        copyToPasteboard(cleaned)
        flashCopied()
        setState(.done)
        // Record the success, keeping the recording linked. We no longer delete it here:
        // it stays in History (bounded by `pruneOldRecordings`) so the entry can be re-run.
        upsertHistory(serbian: serbianText, english: cleaned, status: .completed, error: nil)
        pending = nil
    }

    /// Insert/update the in-flight job's History entry, carrying its recording reference so a
    /// failed entry can be retried later. Reuses `currentRecordID`/`currentRecordDate` so a
    /// retry updates the same entry instead of creating a duplicate.
    private func upsertHistory(serbian: String, english: String, status: RecordStatus, error: String?) {
        guard let history else { return }
        let id = currentRecordID ?? UUID()
        let date = currentRecordDate ?? .now
        currentRecordID = id
        currentRecordDate = date
        let audio = audioReference()
        history.upsert(TranslationRecord(
            id: id,
            date: date,
            serbian: serbian,
            english: english,
            model: whisperModel,
            source: inference.source,
            status: status,
            errorMessage: error,
            audioFileName: audio.audioFileName,
            importedPath: audio.importedPath,
            importedFileName: audio.importedFileName
        ))
    }

    /// The recording behind the current job, as History stores it: a basename for a live
    /// capture we own, or an absolute path for the user's imported file.
    private func audioReference() -> (audioFileName: String?, importedPath: String?, importedFileName: String?) {
        switch pending {
        case .recording(let url): return (url.lastPathComponent, nil, nil)
        case .imported(let url): return (nil, url.path, url.lastPathComponent)
        case nil: return (nil, nil, nil)
        }
    }

    // MARK: Helpers

    private func setEngineStatus(_ status: String?) {
        guard status != engineStatus else { return } // avoid redundant SwiftUI invalidations
        engineStatus = status
    }

    /// Appends a streamed delta to the live partial — only while translating, so a delta that
    /// lands after a cancel/finish can't corrupt the committed result.
    private func appendStreamDelta(_ delta: String) {
        guard case .translating = state else { return }
        streamingText += delta
    }

    /// Reflects a pipeline stage entry in the live stage strip (and the retrieved-notes count).
    private func applyStage(_ progress: PipelineProgress) {
        guard case .translating = state else { return }
        liveStage = progress.stage
        if let count = progress.retrievedCount { resultRetrievedCount = count }
    }

    /// Turns a refinement failure into a user-facing error that keeps the transcript on screen
    /// and offers a way to recover (Retry always re-refines). The "Open LM Studio" action is
    /// offered ONLY when LM Studio is actually the active backend — never for the in-process
    /// MLX engine, whose failures are not fixed by opening LM Studio.
    private func inferenceError(for error: Error) -> AppError {
        let openLMStudio = RecoveryAction(label: "Open LM Studio", kind: .openLMStudio)
        guard let lmError = error as? LMStudioError else {
            // Generic / in-process-engine failure (e.g. InferenceError): plain Retry unless the
            // backend really is LM Studio.
            let action = inference is LMStudioInference ? openLMStudio : nil
            return AppError(message: "Couldn't refine the translation. \(error.localizedDescription)", action: action)
        }
        switch lmError {
        case .cliNotFound:
            return AppError(
                message: "LM Studio's command-line tool (lms) isn't installed, so the translation can't be refined. In LM Studio run “Install lms” (or `npx lmstudio install-cli`), then Retry.",
                action: openLMStudio
            )
        case .notRunning:
            return AppError(message: "LM Studio isn't running. Start it, then Retry.", action: openLMStudio)
        case .modelNotLoaded:
            return AppError(message: "No model is loaded in LM Studio. Load \(TranslationPreferences.model), then Retry.", action: openLMStudio)
        case .setupFailed(let message):
            return AppError(message: "Couldn't get LM Studio ready: \(message)", action: openLMStudio)
        case .other(let message):
            return AppError(message: "LM Studio couldn't refine the translation: \(message)", action: openLMStudio)
        }
    }

    /// Cheap guard against Whisper hallucinating text from silence/noise.
    private func isMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }

    private func clearResults() {
        serbianText = ""
        outputText = ""
        streamingText = ""
        liveStage = nil
        plannedStages = []
        resultRetrievedCount = 0
        translationSource = nil
        notice = nil
        processingDetail = nil
        importedFileName = nil
        transcriptionFraction = 0
        pending = nil
        currentRecordID = nil
        currentRecordDate = nil
    }

    private func setState(_ newState: AppState) {
        Log.recorder.info("state → \(String(describing: newState), privacy: .public)")
        state = newState
        onStateChange?(newState)
    }

    // MARK: Microphone permission

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    // MARK: Metering (drives the pulse)

    private func startMetering() {
        // Timer fires on the main run loop and we're already on the main actor, so
        // update directly instead of allocating a Task per tick (20 Hz).
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLevel() }
        }
    }

    private func updateLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // dBFS, roughly -160...0
        level = Double(max(0, min(1, (power + 55) / 55)))
        levelHistory.append(level)
        if levelHistory.count > 18 { levelHistory.removeFirst(levelHistory.count - 18) }
        recordingDuration = recorder.currentTime
        onLevelChange?(levelHistory)
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: Processing progress (transcription elapsed-time clock)

    private func startProcessingTimer() {
        processingElapsed = 0
        transcriptionFraction = 0
        processingDetail = transcriptionDetail()
        processingTimer?.invalidate()
        // Fires on the main run loop; we're on the main actor.
        processingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.processingElapsed += 1
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.transcriptionFraction = await self.whisper.transcriptionProgress
                    self.processingDetail = self.transcriptionDetail()
                }
            }
        }
    }

    private func stopProcessingTimer() {
        processingTimer?.invalidate()
        processingTimer = nil
    }

    /// Detail under the status line while transcribing: a real percentage + time estimate
    /// once WhisperKit reports progress, otherwise an elapsed clock. Prefixed with the file
    /// name for imports.
    private func transcriptionDetail() -> String {
        let prefix = importedFileName.map { "\($0) · " } ?? ""
        if transcriptionFraction > 0.01 {
            let pct = Int((transcriptionFraction * 100).rounded())
            if let remaining = estimatedRemaining() { return "\(prefix)\(pct)% · ~\(remaining) left" }
            return "\(prefix)\(pct)%"
        }
        return "\(prefix)\(clockString(processingElapsed))"
    }

    /// Projects time-remaining from how long the elapsed fraction took. Needs a couple of
    /// seconds of signal first so the first estimate isn't wild.
    private func estimatedRemaining() -> String? {
        guard transcriptionFraction > 0.02, processingElapsed >= 2 else { return nil }
        let projectedTotal = Double(processingElapsed) / transcriptionFraction
        let remaining = Int((projectedTotal - Double(processingElapsed)).rounded())
        guard remaining > 0 else { return nil }
        return clockString(remaining)
    }

    private func clockString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Durable recording files (so a failed run can be retried)

    private static func newRecordingURL() -> URL {
        let name = "rec-\(timestamp())-\(UUID().uuidString.prefix(6)).wav"
        if let dir = try? Brand.recordingsDirectory() { return dir.appendingPathComponent(name) }
        return Brand.temporaryRecordingURL
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    /// Bound the saved-recordings folder so failed-and-forgotten captures don't pile up
    /// forever, while keeping the most recent ones around to retry.
    private func pruneOldRecordings(keeping limit: Int) {
        guard let dir = try? Brand.recordingsDirectory() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let wavs = files.filter { $0.pathExtension == "wav" }
        guard wavs.count > limit else { return }
        // Never prune a recording that backs a failed History entry — keeping it retryable is
        // the whole point of holding onto it.
        let protected = history?.protectedAudioFileNames ?? []
        let byNewest = wavs.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in byNewest.dropFirst(limit) where !protected.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Clipboard + confirmations

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func flashCopied() {
        showCopiedConfirmation = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showCopiedConfirmation = false
        }
    }

    private func flashNotice(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
