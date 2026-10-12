import XCTest

@MainActor
final class MVPFlowTests: XCTestCase {
    func testDocumentNamingChipsAndWordCloud() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let name = "Names " + String(UUID().uuidString.prefix(6))
        app.buttons["newPipeline"].tap()
        let field = app.textFields["pipelineName"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + name)
        let clear = app.buttons["Clear template"]
        for _ in 0..<8 { if clear.isHittable { break }; app.swipeUp() }
        clear.tap()
        app.buttons["addTemplate-documentDate"].tap()
        app.buttons["addTemplate-underscore"].tap()
        app.buttons["addTemplate-word1"].tap()
        XCTAssertTrue(app.staticTexts["templateExample"].label.contains("2026-10-05_Telekom.pdf"))
        app.buttons["savePipeline"].tap()
        for _ in 0..<20 { if app.buttons["openFixture"].isHittable { break }; app.swipeUp() }
        app.buttons["openFixture"].tap()
        XCTAssertTrue(app.buttons["pipelinePicker"].waitForExistence(timeout: 10))
        app.buttons["pipelinePicker"].tap()
        let option = app.buttons[name].firstMatch
        for _ in 0..<35 { if option.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(option.exists)
        option.tap()
        app.swipeUp()
        app.buttons["runPipeline"].tap()
        XCTAssertTrue(app.buttons["confirmFilename"].waitForExistence(timeout: 10))
        let acme = app.buttons["cloud-acme"]
        for _ in 0..<10 { if acme.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(acme.exists)
        acme.tap()
        XCTAssertTrue(app.staticTexts["proposedFilename"].label.contains("2026-10-05_Acme.pdf"))
        let namingScreenshot = XCTAttachment(screenshot: app.screenshot())
        namingScreenshot.name = "Document naming word cloud"
        namingScreenshot.lifetime = .keepAlways
        add(namingScreenshot)
        app.buttons["confirmFilename"].tap()
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["resultFilename"].value as? String, "2026-10-05_Acme.pdf")
        app.buttons["Discard"].tap()
    }

    func testPipelineFirstImportSaveStepAndSwipeDeletion() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let pipelineName = "Swipe " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["newPipeline"].waitForExistence(timeout: 10))
        app.buttons["newPipeline"].tap()
        let name = app.textFields["pipelineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + pipelineName)
        let ocr = app.switches["enableOCR"]
        XCTAssertTrue(ocr.exists)
        XCTAssertTrue(app.switches["enableRename"].exists)
        tapSwitch(ocr)
        XCTAssertEqual(ocr.value as? String, "1")
        let skipExisting = app.switches["skipExistingText"]
        XCTAssertEqual(skipExisting.value as? String, "1")
        tapSwitch(skipExisting)
        XCTAssertEqual(skipExisting.value as? String, "0")
        tapSwitch(ocr)
        XCTAssertEqual(ocr.value as? String, "0")
        let saving = app.switches["enableSave"]
        if !saving.isHittable { app.swipeUp() }
        XCTAssertTrue(saving.exists)
        tapSwitch(saving)
        app.buttons["savePipeline"].tap()
        XCTAssertTrue(app.alerts["Cannot save pipeline"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        tapSwitch(saving)
        app.buttons["savePipeline"].tap()
        XCTAssertTrue(app.navigationBars["Edit pipeline"].waitForNonExistence(timeout: 5))
        for _ in 0..<10 {
            if app.buttons["importDocument"].exists && app.buttons["importDocument"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["importDocument"].tap()
        XCTAssertTrue(app.navigationBars["Choose a pipeline"].waitForExistence(timeout: 5), app.debugDescription)
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "importPipeline-", pipelineName)).firstMatch
        for _ in 0..<10 {
            if choice.exists && choice.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(choice.exists)
        choice.tap()
        XCTAssertTrue(app.navigationBars["Choose a pipeline"].waitForNonExistence(timeout: 5))
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "Abbrechen")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Choosing a pipeline should present the Files picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pipeline-", pipelineName)).firstMatch
        for _ in 0..<10 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["newPipeline"].waitForExistence(timeout: 10))
        XCTAssertFalse(row.exists, "Deletion must persist across launches")
    }

    private func tapSwitch(_ element: XCUIElement) {
        let control = element.switches.firstMatch
        if control.exists { control.tap() } else { element.tap() }
    }

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
        let createdPipeline = app.buttons[pipelineName].firstMatch
        for _ in 0..<30 {
            if createdPipeline.exists && createdPipeline.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(createdPipeline.exists, app.debugDescription)
        createdPipeline.tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["proposedFilename"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["proposedFilename"].label.hasSuffix("PdfPipe-Test-Invoice.pdf"))
        XCTAssertTrue(app.buttons["runPipeline"].waitForExistence(timeout: 5))
        app.buttons["runPipeline"].tap()
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10))
        app.buttons["Share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5) || app.buttons["Copy"].waitForExistence(timeout: 5))
        let sharing = XCUIApplication(bundleIdentifier: "com.apple.SharingUIService")
        var extensionButton = sharing.cells["PDF Pipe"].firstMatch
        let more = sharing.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "More", "Mehr")).firstMatch
        let targets = sharing.scrollViews.containing(.cell, identifier: "shareCell").firstMatch
        for _ in 0..<12 {
            if (extensionButton.exists && extensionButton.isHittable) || (more.exists && more.isHittable) { break }
            guard targets.exists else { break }
            targets.swipeLeft()
        }
        if !extensionButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(more.waitForExistence(timeout: 5), sharing.debugDescription)
            more.tap()
            extensionButton = sharing.cells.containing(.staticText, identifier: "PDF Pipe").firstMatch
            for _ in 0..<12 {
                if extensionButton.exists && extensionButton.isHittable { break }
                sharing.swipeUp()
            }
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
        screenshot.name = "PDF Pipe share extension"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if extensionUI.buttons["Discard"].exists { extensionUI.buttons["Discard"].tap() }
        else if sharing.buttons["Discard"].exists { sharing.buttons["Discard"].tap() }
        else { app.buttons["Discard"].firstMatch.tap() }
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10), "Discarding the extension must leave the host's export copy available")
    }
}
