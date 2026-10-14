import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func testImportShowsSuggestionsAndRequiresUserNameChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
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
        invoice.tap()
        let selectedInvoice = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "invoice, selected position 1")).firstMatch
        XCTAssertTrue(selectedInvoice.exists)
        let date = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026-10-05")).firstMatch
        XCTAssertTrue(date.exists)
        XCTAssertFalse(date.label.contains("suggested date"))
        date.tap()
        XCTAssertTrue(app.buttons["Share"].isEnabled)
        let chosenName = app.staticTexts["proposedFilename"].label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Name PDF"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["proposedFilename"].label, chosenName)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Name PDF"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["proposedFilename"].waitForExistence(timeout: 40))
        XCTAssertEqual(app.staticTexts["proposedFilename"].label, chosenName)
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 10))
    }
}
