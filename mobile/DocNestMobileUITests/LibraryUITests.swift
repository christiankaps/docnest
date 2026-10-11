import XCTest

@MainActor
final class LibraryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLibraryViewerSearchShareDetailsAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["DOCNEST_UI_TEST_SEED"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Invoice_2"].waitForExistence(timeout: 15))
        app.staticTexts["Invoice"].tap()
        XCTAssertTrue(app.buttons["documentDetails"].waitForExistence(timeout: 5))
        app.buttons["documentDetails"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Invoice.pdf")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let detailsScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailsScreenshot.lifetime = .keepAlways
        add(detailsScreenshot)
        XCTAssertTrue(app.staticTexts["Date needs review"].exists)
        XCTAssertTrue(app.staticTexts["Imported"].exists)
        app.buttons["Done"].tap()
        app.buttons["searchPDF"].tap()
        app.textFields["Search this PDF"].tap()
        app.textFields["Search this PDF"].typeText("ALPHA-123")
        app.buttons["Find"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Page 2").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Page 2").firstMatch.tap()
        app.buttons["More"].tap()
        app.buttons["Export PDF"].tap()
        XCTAssertTrue(app.textFields["DOCPicker.filenameTextField"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.textFields["DOCPicker.filenameTextField"].value as? String, "Invoice")
        let exportScreenshot = XCTAttachment(screenshot: app.screenshot())
        exportScreenshot.lifetime = .keepAlways
        add(exportScreenshot)
        // The system export sheet supports native swipe-to-dismiss; its hidden Cancel AX node is not an action.
        let exportBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        exportBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let shareReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["sharePDF"])
        XCTAssertEqual(XCTWaiter.wait(for: [shareReady], timeout: 5), .completed)
        app.buttons["sharePDF"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Invoice_2"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Invoice"].exists)
        app.tabBars.buttons["Library"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["On this iPhone"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["importPDF"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testEmptyLibraryOffersImportAndSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["Your paperwork, together"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["importPDF"].firstMatch.exists)
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Inbox is empty"].exists)
    }
}
