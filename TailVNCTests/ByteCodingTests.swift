import XCTest
@testable import TailVNC

final class ByteCodingTests: XCTestCase {
    func testBigEndianRoundTrip() throws {
        var data = Data()
        data.appendUInt16BE(0xabcd)
        data.appendUInt32BE(0x1234_5678)

        XCTAssertEqual(try data.uint16BE(at: 0), 0xabcd)
        XCTAssertEqual(try data.uint32BE(at: 2), 0x1234_5678)
    }

    func testBoundsChecking() {
        XCTAssertThrowsError(try Data([1]).uint16BE(at: 0))
        XCTAssertThrowsError(try Data([1, 2, 3]).uint32BE(at: 0))
    }
}
