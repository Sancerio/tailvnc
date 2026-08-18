import XCTest

final class TailVNCUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectionFormIsReadyWithoutEmbeddedEndpoint() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let host = app.textFields["hostField"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertTrue(host.value as? String == "100.x.x.x or MagicDNS name" || (host.value as? String)?.isEmpty == true)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertFalse(app.buttons["connectButton"].isEnabled)
    }
}
