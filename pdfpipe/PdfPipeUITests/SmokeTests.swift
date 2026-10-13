import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func testImportShowsSuggestionsAndRequiresUserNameChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["openFixture"].tap()
        XCTAssertTrue(app.navigationBars["Name PDF"].waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["Share"].isEnabled)
        let date = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026-10-05")).firstMatch
        XCTAssertTrue(date.exists)
        date.tap()
        XCTAssertTrue(app.buttons["Share"].isEnabled)
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 10))
    }
}
