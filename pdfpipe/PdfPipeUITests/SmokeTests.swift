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
        XCTAssertFalse(app.buttons["Share"].isEnabled)
        XCTAssertTrue(app.buttons["Save to Files"].exists)
        let source = app.segmentedControls["textSourcePicker"]
        XCTAssertTrue(source.exists)
        source.buttons["PDF text"].tap()
        XCTAssertTrue(source.buttons["PDF text"].isSelected)
        app.buttons["View full text and diff"].tap()
        XCTAssertTrue(app.navigationBars["Text inspection"].exists)
        XCTAssertTrue(app.staticTexts["Page 1"].exists)
        app.buttons["Diff"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].exists)
        app.buttons["Done"].tap()
        source.buttons["Apple OCR"].tap()
        XCTAssertTrue(source.buttons["Apple OCR"].isSelected)
        source.buttons["PDF text"].tap()
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
