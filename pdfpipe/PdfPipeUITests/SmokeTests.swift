import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func testImportShowsSuggestionsAndRequiresUserNameChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertFalse(app.buttons["Settings"].exists)
        app.buttons["openFixture"].tap()
        XCTAssertTrue(app.navigationBars["Name PDF"].waitForExistence(timeout: 40))
        let origin = app.descendants(matching: .any)["documentOrigin"]
        XCTAssertTrue(origin.exists)
        XCTAssertTrue(origin.label.contains("Likely digital PDF"))
        XCTAssertFalse(app.buttons["Share"].isEnabled)
        XCTAssertTrue(app.buttons["Save to Files"].exists)
        XCTAssertFalse(app.segmentedControls["textSourcePicker"].exists)
        XCTAssertFalse(app.buttons["View full text and diff"].exists)
        app.scrollViews.firstMatch.swipeUp()
        let invoice = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "invoice, not selected")).firstMatch
        XCTAssertTrue(invoice.exists)
        invoice.press(forDuration: 1)
        app.buttons["More important"].tap()
        XCTAssertTrue(invoice.label.contains("rated more important"))
        invoice.press(forDuration: 1)
        app.buttons["Remove rating"].tap()
        XCTAssertTrue(invoice.label.contains("not rated"))
        let date = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026-10-05")).firstMatch
        XCTAssertTrue(date.exists)
        date.tap()
        XCTAssertTrue(app.buttons["Share"].isEnabled)
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 10))
    }
}
