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

    /// Loads and prewarms the model, downloading it from Hugging Face on first run
    /// (~2.9 GB for `openai_whisper-large-v3`). Blocks until the model is ready.
    func load(model: String) async throws {
        guard pipe == nil else { return }
        Log.whisper.info("Loading model \(model, privacy: .public)")
        // prewarm: true runs warm-up at load so the FIRST transcription isn't slow.
        pipe = try await WhisperKit(WhisperKitConfig(model: model, prewarm: true))
        Log.whisper.info("Model ready")
    }

    /// Runs one transcription/translation pass and returns the trimmed text.
    func run(audioPath: String, task: DecodingTask, language: String?) async throws -> String {
        guard let pipe else { throw WhisperEngineError.notLoaded }
        // VAD chunking splits long audio on silence and transcribes each speech
        // segment independently — fixes dropped clauses on long passages (measured
        // WER 25%→18% on a 56s clip) and parallelizes the work across chunks.
        let options = DecodingOptions(task: task, language: language, chunkingStrategy: .vad)
        // `transcribe(audioPath:decodeOptions:)` returns `[TranscriptionResult]` (one
        // entry per chunk); join their text for the full transcript.
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
