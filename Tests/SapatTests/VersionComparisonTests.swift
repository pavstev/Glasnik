import XCTest
@testable import Sapat

final class VersionComparisonTests: XCTestCase {
    func testNewerWhenNumericallyGreater() {
        // Numeric, not lexical — the classic "1.10 vs 1.9" regression.
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.1.0", newerThan: "1.0.5"))
    }

    func testNotNewerWhenEqualOrOlder() {
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.9.0", newerThan: "1.10.0"))
    }
}
