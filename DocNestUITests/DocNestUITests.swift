import XCTest

final class DocNestUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testApplicationLaunches() throws {
        let app = XCUIApplication()
        app.activate()
        XCTAssertNotEqual(app.state, .notRunning)
    }
}