import XCTest
@testable import VSLight

final class VersionPolicyTests: XCTestCase {
    func testForbiddenDigitIsRejected() {
        XCTAssertFalse(VersionPolicy.isAllowed("1.4.0"))
        XCTAssertFalse(VersionPolicy.isAllowed("4.0.0"))
        XCTAssertFalse(VersionPolicy.isAllowed("1.0.4"))
        XCTAssertFalse(VersionPolicy.isAllowed("1.14.0"))
        XCTAssertTrue(VersionPolicy.isAllowed("1.5.0"))
        XCTAssertTrue(VersionPolicy.isAllowed("0.1.0"))
    }

    func testNextMinorSkipsForbiddenDigit() {
        XCTAssertEqual(VersionPolicy.nextMinor(after: "1.3.0"), "1.5.0")
        XCTAssertEqual(VersionPolicy.nextMinor(after: "1.9.0"), "1.10.0")
        XCTAssertEqual(VersionPolicy.nextMinor(after: "1.13.0"), "1.15.0")
        XCTAssertEqual(VersionPolicy.nextMinor(after: "3.39.0"), "3.50.0")
    }

    func testNextPatchSkipsForbiddenDigit() {
        XCTAssertEqual(VersionPolicy.nextPatch(after: "0.1.3"), "0.1.5")
        XCTAssertEqual(VersionPolicy.nextPatch(after: "0.1.13"), "0.1.15")
        XCTAssertEqual(VersionPolicy.nextPatch(after: "0.1.23"), "0.1.25")
    }

    func testInvalidVersionFallsBackToFirstRelease() {
        XCTAssertEqual(VersionPolicy.nextMinor(after: "1.2"), "0.1.0")
        XCTAssertEqual(VersionPolicy.nextPatch(after: "abc"), "0.1.0")
    }
}
