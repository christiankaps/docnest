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
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 15))
        app.buttons["allDocuments"].tap()
        XCTAssertTrue(app.staticTexts["Invoice_2"].waitForExistence(timeout: 5))
        app.staticTexts["Invoice"].tap()
        XCTAssertTrue(app.buttons["documentDetails"].waitForExistence(timeout: 5))
        app.buttons["documentDetails"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Invoice.pdf")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let detailsScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailsScreenshot.lifetime = .keepAlways
        add(detailsScreenshot)
        XCTAssertTrue(app.staticTexts["Date needs review"].exists)
        XCTAssertTrue(app.staticTexts["Imported"].exists)
        app.navigationBars["Details"].buttons["Done"].tap()
        app.buttons["searchPDF"].tap()
        app.textFields["Search this PDF"].tap()
        app.textFields["Search this PDF"].typeText("ALPHA-123")
        app.buttons["Find"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Page 2").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Page 2").firstMatch.tap()
        app.buttons["More"].tap()
        app.buttons["Export PDF"].tap()
        let exportBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(exportBar.waitForExistence(timeout: 10), app.debugDescription)
        if app.textFields["DOCPicker.filenameTextField"].waitForExistence(timeout: 5) {
            XCTAssertEqual(app.textFields["DOCPicker.filenameTextField"].value as? String, "Invoice")
        } else {
            // iOS can present its location screen without a filename field. Copy names/bytes are verified by store tests.
            XCTAssertTrue(app.buttons["DOCPicker.actionButton"].exists, app.debugDescription)
        }
        let exportScreenshot = XCTAttachment(screenshot: app.screenshot())
        exportScreenshot.lifetime = .keepAlways
        add(exportScreenshot)
        // The system export sheet supports native swipe-to-dismiss; its hidden Cancel AX node is not an action.
        exportBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let shareReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["sharePDF"])
        XCTAssertEqual(XCTWaiter.wait(for: [shareReady], timeout: 5), .completed)
        app.buttons["sharePDF"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
        app.buttons["allDocuments"].tap()
        XCTAssertTrue(app.staticTexts["Invoice_2"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Invoice"].exists)
        app.tabBars.buttons["Library"].tap()
        app.navigationBars.buttons["Library"].tap()
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

    func testRenameBulkLabelsAndRecentlyDeletedRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["DOCNEST_UI_TEST_SEED"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 15))
        app.buttons["allDocuments"].tap()
        app.staticTexts["Invoice"].press(forDuration: 1)
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.textFields["Filename"].waitForExistence(timeout: 5))
        let field = app.textFields["Filename"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Invoice.pdf".count) + "Renamed.pdf")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5))
        app.buttons["Select"].tap()
        app.staticTexts["Renamed"].tap()
        app.staticTexts["Invoice_2"].tap()
        app.buttons["Add Labels"].tap()
        XCTAssertTrue(app.buttons["Taxes"].waitForExistence(timeout: 5))
        app.buttons["Taxes"].tap()
        XCTAssertEqual(app.buttons["Taxes"].value as? String, "Selected")
        app.buttons["Save"].tap()
        let shareReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["Share"])
        XCTAssertEqual(XCTWaiter.wait(for: [shareReady], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["2 selected in this list"].exists)
        capture(app, name: "Bulk label selection")
        app.buttons["Share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        capture(app, name: "Bulk PDF sharing")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
        app.buttons["allDocuments"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5))
        app.staticTexts["Renamed"].press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete Document?"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForNonExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["recentlyDeleted"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["recentlyDeleted"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5))
        capture(app, name: "Recently Deleted")
        app.buttons["Recover"].tap()
        XCTAssertTrue(app.staticTexts["No deleted documents"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Library"].tap()
        app.buttons["allDocuments"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Taxes").count, 2)
    }

    private func lockedTestApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["DOCNEST_UI_TEST_SEED"] = "1"
        app.launchEnvironment["DOCNEST_UI_TEST_AUTH"] = "success"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let toggle = app.switches["libraryLockToggle"]
        if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() } else { toggle.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: app.switches["libraryLockToggle"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, app.debugDescription)
        app.navigationBars["Settings"].buttons["Done"].tap()
        return app
    }

    func testLockProtectsPresentedDetailsBackgroundAndColdLaunch() {
        let app = lockedTestApp()
        app.buttons["allDocuments"].tap()
        app.staticTexts["Invoice"].tap()
        app.buttons["documentDetails"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Invoice.pdf")).firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Invoice.pdf"].exists)
        XCTAssertFalse(app.buttons["Edit Labels"].exists)
        capture(app, name: "Neutral locked cover above Details")
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.buttons["Edit Labels"].waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["allDocuments"].exists)
        XCTAssertFalse(app.tabBars.buttons["Inbox"].exists)
        capture(app, name: "Cold-launch locked library")
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let toggle = app.switches["libraryLockToggle"]
        if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() } else { toggle.tap() }
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: app.switches["libraryLockToggle"])
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["unlockLibrary"].exists)
    }

    func testLockLetsNativeShareAndPickerFinishAfterBackground() {
        let app = lockedTestApp()
        app.buttons["allDocuments"].tap()
        app.staticTexts["Invoice"].tap()
        app.buttons["sharePDF"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["documentDetails"].exists)
        capture(app, name: "Native share continues above locked content")
        XCTAssertTrue(app.buttons["header.closeButton"].waitForExistence(timeout: 5))
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.buttons["documentDetails"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Documents"].tap()
        app.navigationBars.buttons["Library"].tap()
        app.buttons["importPDF"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["allDocuments"].exists)
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 5))
    }

    func testLargeTextLockedAuthenticationFailureKeepsRetryReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["DOCNEST_UI_TEST_SEED"] = "1"
        app.launchEnvironment["DOCNEST_UI_TEST_AUTH"] = "failure"
        app.launchEnvironment["DOCNEST_UI_TEST_LOCK_ENABLED"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.buttons["unlockLibrary"].isHittable)
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.staticTexts["Authentication didn’t complete. Try again."].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["unlockLibrary"].isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["allDocuments"].exists)
        capture(app, name: "Large-text locked authentication retry")
        app.terminate()
        app.launchEnvironment["DOCNEST_UI_TEST_AUTH"] = "success"
        app.launch()
        XCTAssertTrue(app.buttons["unlockLibrary"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["unlockLibrary"].tap()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLabelsDatesReviewAndFiltersPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["DOCNEST_UI_TEST_SEED"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 15))
        capture(app, name: "Label-first Library")
        app.tabBars.buttons["Inbox"].tap()
        app.staticTexts["Invoice"].tap()
        app.buttons["documentLabels"].tap()
        app.buttons["Invoices"].tap()
        app.buttons["Taxes"].tap()
        XCTAssertEqual(app.buttons["Invoices"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["Taxes"].value as? String, "Selected")
        capture(app, name: "Multiple label selection")
        app.buttons["Save"].tap()
        app.buttons["documentDetails"].tap()
        XCTAssertTrue(app.staticTexts["Invoices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Taxes"].exists)
        app.buttons["Edit Date"].tap()
        let year = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        year.adjust(toPickerWheelValue: "2024")
        capture(app, name: "Document date editor")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit Date"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Date needs review"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2024'")).firstMatch.exists)
        capture(app, name: "Live updated details")
        app.navigationBars["Details"].buttons["Done"].tap()
        app.buttons["finishReview"].tap()
        XCTAssertTrue(app.buttons["finishReview"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons["Inbox"].tap()
        XCTAssertFalse(app.staticTexts["Invoice"].exists)
        app.staticTexts["Invoice_2"].tap()
        app.buttons["finishReview"].tap()
        XCTAssertTrue(app.buttons["finishReview"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Inbox is empty"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["allDocuments"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Inbox is empty"].exists)
        app.tabBars.buttons["Library"].tap()
        app.buttons["allDocuments"].tap()
        app.buttons["Filter"].tap()
        app.buttons["Invoices"].tap()
        app.buttons["Taxes"].tap()
        app.swipeUp()
        app.buttons["2026"].tap()
        XCTAssertTrue(app.buttons["2026"].isSelected)
        app.buttons["2024"].tap()
        XCTAssertTrue(app.buttons["2024"].isSelected)
        XCTAssertFalse(app.buttons["2026"].isSelected)
        capture(app, name: "Labels and single-year filter")
        app.navigationBars["Filter"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Invoice"].exists)
        XCTAssertFalse(app.staticTexts["Invoice_2"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Clear Filters"].tap()
        XCTAssertTrue(app.staticTexts["Invoice_2"].exists)
    }

    func testCreateRenameAndDeleteLabel() {
        let app = XCUIApplication()
        app.launchEnvironment["DOCNEST_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["manageLabels"].waitForExistence(timeout: 10))
        app.buttons["manageLabels"].tap()
        app.buttons["New Label"].tap()
        let name = app.textFields["Label name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Personal")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Personal"].waitForExistence(timeout: 5))
        app.buttons["Personal"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Family")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Family"].waitForExistence(timeout: 5))
        app.buttons["Family"].swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["Delete Label"].tap()
        XCTAssertTrue(app.buttons["Family"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["manageLabels"].waitForExistence(timeout: 10))
        app.buttons["manageLabels"].tap()
        XCTAssertFalse(app.buttons["Personal"].exists)
        XCTAssertFalse(app.buttons["Family"].exists)
    }

}
