import XCTest
@testable import Sapat

/// Verifies the mechanical output sanitizer strips LM scaffolding while NEVER eating
/// real content — the guard cases encode the reviewed false-positive scenarios.
/// Generated case table; runs in CI under the Command Line Tools.
final class OutputSanitizerTests: XCTestCase {
    func testCase01() {
        // Leading label line ending in colon, content below -> label removed.
        XCTAssertEqual(OutputSanitizer.sanitize("Here is the translation:\nThe deployment pipeline runs the integration tests before promoting the build."), "The deployment pipeline runs the integration tests before promoting the build.")
    }

    func testCase02() {
        // Whole output wrapped in straight quotes, no inner quotes -> unwrapped.
        XCTAssertEqual(OutputSanitizer.sanitize("\"The cache is invalidated whenever the underlying record changes.\""), "The cache is invalidated whenever the underlying record changes.")
    }

    func testCase03() {
        // Smart double quotes wrapping the output -> unwrapped.
        XCTAssertEqual(OutputSanitizer.sanitize("“We should debounce the search input by 300 milliseconds.”"), "We should debounce the search input by 300 milliseconds.")
    }

    func testCase04() {
        // German-style low-high quotes wrapping the output -> unwrapped.
        XCTAssertEqual(OutputSanitizer.sanitize("„Ovo je recenica.“"), "Ovo je recenica.")
    }

    func testCase05() {
        // Plain code fence wraps the output -> fence removed, inner single quotes kept.
        XCTAssertEqual(OutputSanitizer.sanitize("```\nThe migration adds a non-null status column with a default of 'pending'.\n```"), "The migration adds a non-null status column with a default of 'pending'.")
    }

    func testCase06() {
        // Fence with a bare language tag -> tag + fences removed.
        XCTAssertEqual(OutputSanitizer.sanitize("```text\nThe API returns 429 when the rate limit is exceeded.\n```"), "The API returns 429 when the rate limit is exceeded.")
    }

    func testCase07() {
        // Inline lead-in 'Sure, ' (comma + space) -> removed.
        XCTAssertEqual(OutputSanitizer.sanitize("Sure, the authentication token expires after fifteen minutes of inactivity."), "the authentication token expires after fifteen minutes of inactivity.")
    }

    func testCase08() {
        // Inline lead-in 'Certainly! ' -> removed.
        XCTAssertEqual(OutputSanitizer.sanitize("Certainly! The two services communicate over gRPC."), "The two services communicate over gRPC.")
    }

    func testCase09() {
        // Trailing self-identifying note ('I translated ...') -> removed.
        XCTAssertEqual(OutputSanitizer.sanitize("The two services communicate over gRPC.\nI translated this from the Serbian."), "The two services communicate over gRPC.")
    }

    func testCase10() {
        // Trailing self-identifying note ('Let me know ...') -> removed.
        XCTAssertEqual(OutputSanitizer.sanitize("Use exponential backoff for retries.\nLet me know if you want anything else."), "Use exponential backoff for retries.")
    }

    func testCase11() {
        // Leaked <think> block (Qwen3) -> removed.
        XCTAssertEqual(OutputSanitizer.sanitize("<think>The speaker describes slow startup; state it once.</think>\nThe application has slow startup performance."), "The application has slow startup performance.")
    }

    func testCase12() {
        // Single-line label glued to content -> left untouched (acceptable false negative).
        XCTAssertEqual(OutputSanitizer.sanitize("Translation: The service retries failed requests with exponential backoff."), "Translation: The service retries failed requests with exponential backoff.")
    }

    func testCase13() {
        // Inner quotes, not whole-output wrapped -> untouched.
        XCTAssertEqual(OutputSanitizer.sanitize("He said \"no\" and then he said \"yes\"."), "He said \"no\" and then he said \"yes\".")
    }

    func testCase14() {
        // Quoted word that reappears + leading quote -> not unwrapped, lead-in does not fire.
        XCTAssertEqual(OutputSanitizer.sanitize("\"Sure\" is the codename we chose for the release."), "\"Sure\" is the codename we chose for the release.")
    }

    func testCase15() {
        // Single inline backtick span, not a triple fence -> untouched.
        XCTAssertEqual(OutputSanitizer.sanitize("`status: pending`"), "`status: pending`")
    }

    func testCase16() {
        // Fence does NOT wrap the whole output (prose follows) -> untouched.
        XCTAssertEqual(OutputSanitizer.sanitize("```swift\nlet x = compute()\n```\n\nThat snippet shows the call."), "```swift\nlet x = compute()\n```\n\nThat snippet shows the call.")
    }

    func testCase17() {
        // GUARD: 'OK' label + colon -> not eaten (ok/okay excluded, ':' not a separator).
        XCTAssertEqual(OutputSanitizer.sanitize("OK: this is the label shown on the confirm button."), "OK: this is the label shown on the confirm button.")
    }

    func testCase18() {
        // GUARD: 'OK,' as a list head -> not eaten (ok/okay excluded).
        XCTAssertEqual(OutputSanitizer.sanitize("OK, Cancel, and Retry are the three button labels."), "OK, Cancel, and Retry are the three button labels.")
    }

    func testCase19() {
        // GUARD: 'ok-ish' -> not mangled into 'ish' (ok excluded, '-' not a separator).
        XCTAssertEqual(OutputSanitizer.sanitize("ok-ish latency was observed under load."), "ok-ish latency was observed under load.")
    }

    func testCase20() {
        // GUARD: trailing 'Note that ...' caveat is real content -> preserved.
        XCTAssertEqual(OutputSanitizer.sanitize("The scheduler runs every hour.\nNote that the first run is delayed by the warmup period."), "The scheduler runs every hour.\nNote that the first run is delayed by the warmup period.")
    }

    func testCase21() {
        // GUARD: trailing 'If you need ...' conditional is real content -> preserved.
        XCTAssertEqual(OutputSanitizer.sanitize("The config supports two backends.\nIf you need Redis, set the cache driver to redis."), "The config supports two backends.\nIf you need Redis, set the cache driver to redis.")
    }

    func testCase22() {
        // GUARD: 'This translation layer' is a domain noun -> preserved.
        XCTAssertEqual(OutputSanitizer.sanitize("The system has two layers.\nThis translation layer maps domain events to protobuf messages."), "The system has two layers.\nThis translation layer maps domain events to protobuf messages.")
    }

    func testCase23() {
        // GUARD: trailing 'Note: roll back ...' instruction -> preserved.
        XCTAssertEqual(OutputSanitizer.sanitize("Deploy to staging first.\nNote: roll back immediately if the error rate exceeds two percent."), "Deploy to staging first.\nNote: roll back immediately if the error rate exceeds two percent.")
    }

    func testCase24() {
        // GUARD: dictated list + 'Steps:' header -> fully preserved.
        XCTAssertEqual(OutputSanitizer.sanitize("Steps:\n1. Build the image.\n2. Run the tests.\n3. Ship it."), "Steps:\n1. Build the image.\n2. Run the tests.\n3. Ship it.")
    }

    func testCase25() {
        // Surrounding whitespace trimmed; no scaffolding.
        XCTAssertEqual(OutputSanitizer.sanitize("   The retry budget is capped at three attempts per request.   "), "The retry budget is capped at three attempts per request.")
    }

    func testCase26() {
        // Clean output -> unchanged (idempotency anchor).
        XCTAssertEqual(OutputSanitizer.sanitize("The pipeline is green."), "The pipeline is green.")
    }

    func testIdempotent() {
        let inputs: [String] = [
            "Here is the translation:\nThe deployment pipeline runs the integration tests before promoting the build.",
            "\"The cache is invalidated whenever the underlying record changes.\"",
            "“We should debounce the search input by 300 milliseconds.”",
            "„Ovo je recenica.“",
            "```\nThe migration adds a non-null status column with a default of 'pending'.\n```",
            "```text\nThe API returns 429 when the rate limit is exceeded.\n```",
            "Sure, the authentication token expires after fifteen minutes of inactivity.",
            "Certainly! The two services communicate over gRPC.",
            "The two services communicate over gRPC.\nI translated this from the Serbian.",
            "Use exponential backoff for retries.\nLet me know if you want anything else.",
            "<think>The speaker describes slow startup; state it once.</think>\nThe application has slow startup performance.",
            "Translation: The service retries failed requests with exponential backoff.",
            "He said \"no\" and then he said \"yes\".",
            "\"Sure\" is the codename we chose for the release.",
            "`status: pending`",
            "```swift\nlet x = compute()\n```\n\nThat snippet shows the call.",
            "OK: this is the label shown on the confirm button.",
            "OK, Cancel, and Retry are the three button labels.",
            "ok-ish latency was observed under load.",
            "The scheduler runs every hour.\nNote that the first run is delayed by the warmup period.",
            "The config supports two backends.\nIf you need Redis, set the cache driver to redis.",
            "The system has two layers.\nThis translation layer maps domain events to protobuf messages.",
            "Deploy to staging first.\nNote: roll back immediately if the error rate exceeds two percent.",
            "Steps:\n1. Build the image.\n2. Run the tests.\n3. Ship it.",
            "   The retry budget is capped at three attempts per request.   ",
            "The pipeline is green.",
        ]
        for input in inputs {
            let once = OutputSanitizer.sanitize(input)
            XCTAssertEqual(OutputSanitizer.sanitize(once), once, "sanitize must be idempotent")
        }
    }
}
