import XCTest
@testable import TailVNC

final class RemoteViewportTests: XCTestCase {
    func testFittedRectPreservesRemoteAspectRatio() {
        let rect = RemoteViewport.fittedRect(
            remoteSize: CGSize(width: 1_440, height: 900),
            in: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(rect.width, 390, accuracy: 0.001)
        XCTAssertEqual(rect.height, 243.75, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 195, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 422, accuracy: 0.001)
    }

    func testTransformedRectAppliesZoomAndPan() {
        let rect = CGRect(x: 0, y: 100, width: 390, height: 244)
        let transformed = RemoteViewport.transformedRect(
            rect,
            scale: 2,
            offset: CGSize(width: 20, height: -10)
        )

        XCTAssertEqual(transformed.width, 780, accuracy: 0.001)
        XCTAssertEqual(transformed.height, 488, accuracy: 0.001)
        XCTAssertEqual(transformed.midX, rect.midX + 20, accuracy: 0.001)
        XCTAssertEqual(transformed.midY, rect.midY - 10, accuracy: 0.001)
    }

    func testPanIsClampedToVisibleRemoteBounds() {
        let offset = RemoteViewport.clampedOffset(
            CGSize(width: 400, height: 80),
            displayRect: CGRect(x: 0, y: 300, width: 390, height: 244),
            scale: 2,
            available: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(offset.width, 195, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }

    func testRemotePointUsesZoomedAndPannedRect() {
        let point = RemoteViewport.remotePoint(
            CGPoint(x: 200, y: 150),
            transformedRect: CGRect(x: 100, y: 50, width: 200, height: 200),
            remoteSize: CGSize(width: 1_000, height: 500)
        )

        XCTAssertEqual(point?.x, 500)
        XCTAssertEqual(point?.y, 250)
    }

    func testAnchorOffsetKeepsPinchFocalPointStable() {
        let offset = RemoteViewport.offsetKeepingAnchor(
            CGPoint(x: 100, y: 300),
            available: CGSize(width: 400, height: 800),
            startScale: 1,
            targetScale: 2,
            startOffset: .zero
        )

        XCTAssertEqual(offset.width, 100, accuracy: 0.001)
        XCTAssertEqual(offset.height, 100, accuracy: 0.001)
    }
}
