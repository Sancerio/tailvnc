import UIKit
import XCTest
@testable import TailVNC

@MainActor
final class CaptureTextFieldTests: XCTestCase {
    func testMirroringStyleTextAssignmentIsForwardedAndCleared() {
        let field = CaptureTextField()
        var forwarded: [String] = []
        field.onText = { forwarded.append($0) }

        field.text = "abc"

        XCTAssertEqual(forwarded, ["abc"])
        XCTAssertEqual(field.text, "")
    }

    func testNormalKeyboardInputIsForwardedWithoutLocalText() {
        let field = CaptureTextField()
        var forwarded: [String] = []
        field.onText = { forwarded.append($0) }

        field.insertText("x")

        XCTAssertEqual(forwarded, ["x"])
        XCTAssertTrue(field.text?.isEmpty ?? true)
    }

    func testDeleteIsForwarded() {
        let field = CaptureTextField()
        var deleteCount = 0
        field.onDelete = { deleteCount += 1 }

        field.deleteBackward()

        XCTAssertEqual(deleteCount, 1)
    }
}
