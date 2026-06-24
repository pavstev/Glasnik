import Foundation

/// The single source of truth for what the UI is doing.
///
/// `preparing` covers the launch-time model prewarm + microphone request. The
/// optional progress is reserved for a download percentage if we wire one up; it is
/// `nil` for an indeterminate "preparing" spinner.
enum AppState: Equatable {
    case preparing(progress: Double?)
    case idle
    case recording
    case transcribing
    case translating
    case done
    case error(AppError)
}

/// A failure the user should see, optionally with a one-tap recovery action.
struct AppError: Equatable {
    var message: String
    var action: RecoveryAction?
}

/// A non-blocking hint shown alongside a successful result — used when we fell back
/// to offline Whisper translation because LM Studio wasn't available.
struct AppHint: Equatable {
    var message: String
    var action: RecoveryAction?
}

/// A button the popover can render to help the user recover or improve the result.
struct RecoveryAction: Equatable {
    enum Kind: Equatable {
        case openMicrophoneSettings
        case openLMStudio
        case copyCommand(String)
    }

    var label: String
    var kind: Kind
}

/// Which engine produced the English translation.
enum TranslationSource: Equatable {
    case lmStudio        // refined by the local LM Studio model
    case whisperFallback // Whisper's own translate task (offline baseline)
}
