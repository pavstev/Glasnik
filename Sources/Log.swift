import OSLog

/// Centralized os.Logger access. View logs in Console.app or `log stream --predicate
/// 'subsystem == "com.stevanpavlovic.Glasnik"'`.
enum Log {
    private static let subsystem = "com.stevanpavlovic.Glasnik"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let whisper = Logger(subsystem: subsystem, category: "whisper")
    static let ollama = Logger(subsystem: subsystem, category: "ollama")
    static let update = Logger(subsystem: subsystem, category: "update")
}
