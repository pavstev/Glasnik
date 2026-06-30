import Foundation
@testable import Sapat

/// A scriptable `Inference` for tests: records every request and returns whatever the
/// `responder` produces for that call index, so we can assert chunk/merge behaviour and drive
/// the structured/repair paths deterministically without a real model.
final class MockInference: Inference, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [InferenceRequest] = []
    private var callCount = 0
    private let contextWindowValue: Int
    private let responder: @Sendable (InferenceRequest, Int) -> String

    init(contextWindow: Int = 8192, responder: @escaping @Sendable (InferenceRequest, Int) -> String) {
        self.contextWindowValue = contextWindow
        self.responder = responder
    }

    /// Convenience: always return the same fixed string.
    convenience init(contextWindow: Int = 8192, fixed: String) {
        self.init(contextWindow: contextWindow) { _, _ in fixed }
    }

    func prepare(onStatus: @escaping @Sendable (String?) -> Void) async throws {}

    func generate(_ request: InferenceRequest) async throws -> String {
        let index = lock.withLock { () -> Int in
            let current = callCount
            callCount += 1
            _requests.append(request)
            return current
        }
        return responder(request, index)
    }

    var contextWindow: Int { get async { contextWindowValue } }

    var requests: [InferenceRequest] {
        lock.withLock { _requests }
    }

    var generateCallCount: Int {
        lock.withLock { callCount }
    }
}
