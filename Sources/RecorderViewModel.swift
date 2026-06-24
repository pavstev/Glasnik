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

    // MARK: Observed state (read by the view)
    private(set) var state: AppState = .preparing(progress: nil)
    private(set) var level: Double = 0 // mic level 0...1, drives the record-button pulse
    private(set) var levelHistory: [Double] = [] // recent levels for the menu-bar waveform
    private(set) var recordingDuration: TimeInterval = 0 // elapsed seconds, shown while recording
    private(set) var serbianText = ""
    private(set) var englishText = ""
    private(set) var translationSource: TranslationSource?
    private(set) var hint: AppHint?
    private(set) var notice: String? // transient info, e.g. "No speech detected"
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

    // MARK: Dependencies
    private let whisper = WhisperEngine()
    private let llm = LMStudioClient()

    /// Translation history store; set by AppDelegate.
    var history: HistoryStore?

    // MARK: Recording internals
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
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
        } catch {
            setState(.error(AppError(
                message: "Couldn't load the speech model. \(error.localizedDescription)",
                action: nil
            )))
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

    func retryAfterError() {
        Task { await prepare() }
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
    func copyEnglish() {
        guard !englishText.isEmpty else { return }
        copyToPasteboard(englishText)
        flashCopied()
    }

    // MARK: Recording

    private func startRecording() {
        clearResults()

        let url = Brand.temporaryRecordingURL
        try? FileManager.default.removeItem(at: url)

        // 16 kHz mono 16-bit PCM WAV — exactly what WhisperKit wants. AVAudioRecorder
        // handles the conversion from the hardware format internally.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
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

        guard let url = recordingURL, duration > 0.3 else {
            flashNotice("No speech detected — try again")
            setState(.idle)
            return
        }
        Task { await process(url: url) }
    }

    private func process(url: URL) async {
        setState(.transcribing)
        do {
            let serbian = try await whisper.run(audioPath: url.path, task: .transcribe, language: sourceLanguage)
            guard isMeaningful(serbian) else {
                flashNotice("No speech detected — try again")
                setState(.idle)
                return
            }
            serbianText = serbian

            setState(.translating)
            do {
                // Preferred path: the local LM Studio model refines the Serbian source
                // directly, honoring the user's tone + glossary preferences.
                let english = try await llm.translate(
                    serbian,
                    tone: TranslationPreferences.tone,
                    glossary: TranslationPreferences.glossary
                )
                finish(english: english, source: .lmStudio, hint: nil)
            } catch {
                // LM Studio unavailable — fall back to Whisper's own translate task.
                let english = try await whisper.run(audioPath: url.path, task: .translate, language: sourceLanguage)
                finish(english: english, source: .whisperFallback, hint: fallbackHint(for: error))
            }
        } catch {
            setState(.error(AppError(
                message: "Transcription failed. \(error.localizedDescription)",
                action: nil
            )))
        }
    }

    private func finish(english: String, source: TranslationSource, hint: AppHint?) {
        let cleaned = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            setState(.error(AppError(message: "The translation came back empty.", action: nil)))
            return
        }
        englishText = cleaned
        translationSource = source
        self.hint = hint
        copyToPasteboard(cleaned)
        flashCopied()
        setState(.done)
        saveToHistory(serbian: serbianText, english: cleaned, source: source)
    }

    private func saveToHistory(serbian: String, english: String, source: TranslationSource) {
        history?.add(
            serbian: serbian,
            english: english,
            model: whisperModel,
            source: source == .lmStudio ? "LM Studio" : "Whisper"
        )
    }

    // MARK: Helpers

    private func fallbackHint(for error: Error) -> AppHint {
        guard let lmStudioError = error as? LMStudioError else {
            return AppHint(message: "Translated offline by Whisper.", action: nil)
        }
        switch lmStudioError {
        case .notRunning:
            return AppHint(
                message: "Translated offline by Whisper. Start LM Studio’s server for refined output.",
                action: RecoveryAction(label: "Open LM Studio", kind: .openLMStudio)
            )
        case .modelNotLoaded:
            return AppHint(
                message: "Translated offline by Whisper. Load a model in LM Studio for refined output.",
                action: RecoveryAction(label: "Open LM Studio", kind: .openLMStudio)
            )
        case .other(let message):
            return AppHint(message: "Translated offline by Whisper. (LM Studio: \(message))", action: nil)
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
        englishText = ""
        translationSource = nil
        hint = nil
        notice = nil
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
