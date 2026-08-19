import XCTest

final class TailVNCUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectionFormIsReadyWithoutEmbeddedEndpoint() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-ui-testing"]
        app.launch()

        let host = app.textFields["hostField"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertTrue(host.value as? String == "100.x.x.x or MagicDNS name" || (host.value as? String)?.isEmpty == true)
        XCTAssertTrue(app.textFields["usernameField"].exists)
        XCTAssertTrue(app.secureTextFields["macPasswordField"].exists)
        XCTAssertFalse(app.buttons["connectButton"].isEnabled)
    }

    func testPinchZoomShowsIndicatorAndCanBeReset() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-ui-testing", "-ui-testing-remote"]
        app.launch()

        let viewport = app.otherElements["remoteViewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        viewport.pinch(withScale: 2, velocity: 1)

        let zoomIndicator = app.staticTexts["zoomIndicator"]
        XCTAssertTrue(zoomIndicator.waitForExistence(timeout: 2))

        app.buttons["controlsToggleButton"].tap()
        XCTAssertTrue(app.buttons["qualityMenu"].waitForExistence(timeout: 2))
        let resetZoom = app.buttons["resetZoomButton"]
        XCTAssertTrue(resetZoom.waitForExistence(timeout: 2))
        resetZoom.tap()
        XCTAssertFalse(zoomIndicator.waitForExistence(timeout: 0.5))
    }
}
