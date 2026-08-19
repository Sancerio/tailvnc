import XCTest
@testable import TailVNC

final class RFBPerformanceModeTests: XCTestCase {
    func testModesTradeBandwidthForImageQuality() {
        XCTAssertLessThan(
            RFBPerformanceMode.responsive.jpegQualityLevel,
            RFBPerformanceMode.balanced.jpegQualityLevel
        )
        XCTAssertLessThan(
            RFBPerformanceMode.balanced.jpegQualityLevel,
            RFBPerformanceMode.sharp.jpegQualityLevel
        )
        XCTAssertEqual(
            RFBPerformanceMode.responsive.orderedEncodings,
            [7, 0, -223, -255, -30]
        )
        XCTAssertEqual(RFBPerformanceMode.sharp.jpegQualityEncoding, -23)
    }
}
