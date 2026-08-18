import XCTest
@testable import TailVNC

final class RFBFrameBufferTests: XCTestCase {
    func testBGRAIsConvertedToRGBA() throws {
        var framebuffer = try RFBFrameBuffer(width: 2, height: 1)
        let pixels = Data([
            0x10, 0x20, 0x30, 0x00,
            0x40, 0x50, 0x60, 0x00
        ])

        try framebuffer.applyRawBGRA(x: 0, y: 0, width: 2, height: 1, pixels: pixels)

        XCTAssertEqual(
            Array(framebuffer.rgba),
            [0x30, 0x20, 0x10, 0xff, 0x60, 0x50, 0x40, 0xff]
        )
        XCTAssertNotNil(framebuffer.makeImage())
    }

    func testRejectsOutOfBoundsRectangle() throws {
        var framebuffer = try RFBFrameBuffer(width: 2, height: 2)
        XCTAssertThrowsError(
            try framebuffer.applyRawBGRA(
                x: 1,
                y: 1,
                width: 2,
                height: 2,
                pixels: Data(repeating: 0, count: 16)
            )
        )
    }
}
