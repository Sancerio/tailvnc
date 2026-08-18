import UIKit
import XCTest
@testable import TailVNC

@MainActor
final class CaptureTextFieldTests: XCTestCase {
    func testMirroringEditingChangeIsForwardedAndCleared() {
        let field = CaptureTextField()
        var forwarded: [String] = []
        field.onText = { forwarded.append($0) }
        field.installInputBridge()

        field.text = "abc"
        field.sendActions(for: .editingChanged)

        XCTAssertEqual(forwarded, ["abc"])
        XCTAssertEqual(field.text, "")
    }

    func testMirroringTextChangeNotificationIsForwardedAndCleared() {
        let field = CaptureTextField()
        var forwarded: [String] = []
        field.onText = { forwarded.append($0) }
        field.installInputBridge()

        field.text = "xyz"
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)

        XCTAssertEqual(forwarded, ["xyz"])
        XCTAssertEqual(field.text, "")
    }

    func testNormalKeyboardInputIsForwardedWithoutLocalText() {
        let field = CaptureTextField()
        var forwarded: [String] = []
        field.onText = { forwarded.append($0) }
        field.installInputBridge()

        field.insertText("x")

        XCTAssertEqual(forwarded, ["x"])
        XCTAssertTrue(field.text?.isEmpty ?? true)
    }

    func testDeleteIsForwarded() {
        let field = CaptureTextField()
        var deleteCount = 0
        field.onDelete = { deleteCount += 1 }
        field.installInputBridge()

        field.deleteBackward()

        XCTAssertEqual(deleteCount, 1)
    }

    func testReturnIsForwardedAsRemoteReturnKey() {
        let field = CaptureTextField()
        var returnCount = 0
        var forwarded: [String] = []
        field.onReturn = { returnCount += 1 }
        field.onText = { forwarded.append($0) }
        field.installInputBridge()

        field.insertText("\n")

        XCTAssertEqual(returnCount, 1)
        XCTAssertTrue(forwarded.isEmpty)
    }
}
