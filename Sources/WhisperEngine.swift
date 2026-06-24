import Foundation
import WhisperKit

/// Thin wrapper around WhisperKit. An `actor` so the (non-`Sendable`) `WhisperKit`
/// pipeline is only ever touched from one isolation domain.
///
/// We run two kinds of passes over the same recording:
///   - `.transcribe` with `language: "sr"` → the Serbian text we display.
///   - `.translate`                        → English (Whisper's offline fallback).
actor WhisperEngine {
    private var pipe: WhisperKit?

    var isLoaded: Bool { pipe != nil }

    /// Locates the model (downloading it from Hugging Face on first run, ~2.9 GB for
    /// `openai_whisper-large-v3`) and prewarms it. `onDownloadProgress` reports the
    /// download fraction (0–1); it only ticks on first run — a cached model resolves
    /// instantly and prewarm proceeds straight to loading.
    func load(model: String, onDownloadProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard pipe == nil else { return }
        Log.whisper.info("Locating model \(model, privacy: .public)")
        let folder = try await WhisperKit.download(variant: model) { progress in
            onDownloadProgress(progress.fractionCompleted)
        }
        Log.whisper.info("Loading + prewarming model")
        // prewarm: true runs warm-up at load so the FIRST transcription isn't slow.
        // download: false — we already have the local folder from the step above.
        pipe = try await WhisperKit(WhisperKitConfig(model: model, modelFolder: folder.path, prewarm: true, download: false))
        Log.whisper.info("Model ready")
    }

    /// Runs one transcription/translation pass and returns the trimmed text.
    func run(audioPath: String, task: DecodingTask, language: String?) async throws -> String {
        guard let pipe else { throw WhisperEngineError.notLoaded }
        // Tuned for long, pause-heavy monologues (5–10 min of thinking out loud).
        let options = DecodingOptions(
            task: task,
            language: language,
            // Greedy decode with temperature fallback: robust without runaway compute.
            temperature: 0,
            temperatureFallbackCount: 5,
            // Don't let a segment open with a blank/early-stop — cuts empty and
            // degenerate output during the speaker's quiet thinking pauses.
            suppressBlank: true,
            // Silence boundaries. A segment is treated as silence and dropped only when
            // it is BOTH low-confidence (logProb) and high no-speech probability — so
            // genuine quiet speech is kept while true silence is skipped, and a repeating
            // hallucination (high compression ratio) is rejected. These bound the
            // "clean up the quiet moments" behaviour so it never eats real content.
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            // VAD splits the recording on silence and transcribes each speech segment
            // independently — accurate on long passages, and efficient because the quiet
            // gaps are skipped entirely and the chunks decode concurrently on macOS.
            chunkingStrategy: .vad
        )
        // `transcribe` returns one `TranscriptionResult` per chunk; join for the transcript.
        let results = try await pipe.transcribe(audioPath: audioPath, decodeOptions: options)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperEngineError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .notLoaded: return "The speech model isn't loaded yet."
        }
    }
}
