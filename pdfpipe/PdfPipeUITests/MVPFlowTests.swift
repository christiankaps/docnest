import XCTest

@MainActor
final class MVPFlowTests: XCTestCase {
    func testPipelineCreationImportReviewAndShareTarget() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        let pipelineName = "Review " + String(UUID().uuidString.prefix(6))
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["newPipeline"].waitForExistence(timeout: 10))
        app.buttons["newPipeline"].tap()
        let name = app.textFields["pipelineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + pipelineName)
        app.buttons["savePipeline"].tap()
        for _ in 0..<6 {
            if app.buttons["openFixture"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["openFixture"].waitForExistence(timeout: 5))
        app.buttons["openFixture"].tap()
        XCTAssertTrue(app.buttons["pipelinePicker"].waitForExistence(timeout: 10))
        app.buttons["pipelinePicker"].tap()
        app.buttons[pipelineName].firstMatch.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["runPipeline"].waitForExistence(timeout: 5))
        app.buttons["runPipeline"].tap()
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10))
        app.buttons["Share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5) || app.buttons["Copy"].waitForExistence(timeout: 5))
        let sharing = XCUIApplication(bundleIdentifier: "com.apple.SharingUIService")
        let extensionButton = sharing.cells["PdfPipe"].firstMatch
        if !extensionButton.waitForExistence(timeout: 5) {
            let more = sharing.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "More", "Mehr")).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5), sharing.debugDescription)
            more.tap()
        }
        XCTAssertTrue(extensionButton.waitForExistence(timeout: 5), sharing.debugDescription)
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "System share target"
        sheet.lifetime = .keepAlways
        add(sheet)
        extensionButton.tap()
        let extensionUI = XCUIApplication(bundleIdentifier: "com.kaps.pdfpipe.share")
        let chooser = extensionUI.buttons["pipelinePicker"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 10) || app.buttons["pipelinePicker"].exists || sharing.buttons["pipelinePicker"].exists,
                      extensionUI.debugDescription)
        XCTAssertTrue(extensionUI.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "PdfPipe-Test-Invoice.pdf")).firstMatch.exists,
                      "The receiving extension should preserve the supplied output filename")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PdfPipe share extension"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if extensionUI.buttons["Discard"].exists { extensionUI.buttons["Discard"].tap() }
        else if sharing.buttons["Discard"].exists { sharing.buttons["Discard"].tap() }
        else { app.buttons["Discard"].firstMatch.tap() }
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10), "Discarding the extension must leave the host's export copy available")
    }
}
