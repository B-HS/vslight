import XCTest
@testable import VSLight

final class VolumeFormatterTests: XCTestCase {
    func testPercentFormatting() {
        XCTAssertEqual(VolumeFormatter.percent(0.637, decimals: 1), "63.7")
        XCTAssertEqual(VolumeFormatter.percent(0.637, decimals: 0), "64")
        XCTAssertEqual(VolumeFormatter.percent(0.637, decimals: 3), "63.700")
        XCTAssertEqual(VolumeFormatter.percent(0, decimals: 1), "0.0")
        XCTAssertEqual(VolumeFormatter.percent(1, decimals: 1), "100.0")
    }

    func testParsingPercentInput() {
        XCTAssertEqual(VolumeFormatter.parsePercent("63.7") ?? -1, 0.637, accuracy: 0.0001)
        XCTAssertEqual(VolumeFormatter.parsePercent("63,7%") ?? -1, 0.637, accuracy: 0.0001)
        XCTAssertEqual(VolumeFormatter.parsePercent(" 150 ") ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(VolumeFormatter.parsePercent("-10") ?? -1, 0, accuracy: 0.0001)
        XCTAssertNil(VolumeFormatter.parsePercent("abc"))
        XCTAssertNil(VolumeFormatter.parsePercent(""))
    }
}
