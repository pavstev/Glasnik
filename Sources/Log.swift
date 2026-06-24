import OSLog

/// Centralized os.Logger access. View logs in Console.app or `log stream --predicate
/// 'subsystem == "com.stevanpavlovic.Sapat"'`.
enum Log {
    private static let subsystem = Brand.bundleID
    static let app = Logger(subsystem: subsystem, category: "app")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let whisper = Logger(subsystem: subsystem, category: "whisper")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let update = Logger(subsystem: subsystem, category: "update")
}
