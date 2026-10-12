import XCTest

@MainActor
final class MVPFlowTests: XCTestCase {
    func testSelectedFolderAllowsSavingPipeline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["newPipeline"].tap()
        let saving = app.switches["enableSave"]
        if !saving.isHittable { app.swipeUp() }
        tapSwitch(saving)
        XCTAssertEqual(saving.value as? String, "1", app.debugDescription)
        for _ in 0..<8 { if app.buttons["chooseSaveFolder"].isHittable { break }; app.swipeUp() }
        app.buttons["chooseSaveFolder"].tap()
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Browse"].tap()
        XCTAssertTrue(app.staticTexts["On My iPhone"].waitForExistence(timeout: 15), app.debugDescription)
        app.staticTexts["On My iPhone"].tap()
        let folderCell = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@", ", Folder")).firstMatch
        let folderName: String
        if !folderCell.waitForExistence(timeout: 3) {
            let more = app.buttons["OverflowBarButtonItem"]
            XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
            more.tap()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.13)).tap()
            XCTAssertTrue(folderCell.waitForExistence(timeout: 10), app.debugDescription)
            folderName = String(folderCell.identifier.split(separator: ",").first ?? "")
            // Files enters the newly created folder when its name is confirmed.
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        } else {
            folderName = String(folderCell.identifier.split(separator: ",").first ?? "")
            folderCell.tap()
        }
        XCTAssertFalse(folderName.isEmpty)
        let selectFolder = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(selectFolder.waitForExistence(timeout: 5), app.debugDescription)
        selectFolder.tap()
        let folder = app.buttons["chooseSaveFolder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        let selected = expectation(for: NSPredicate(format: "label CONTAINS %@", folderName), evaluatedWith: folder)
        let status = XCTWaiter.wait(for: [selected], timeout: 10)
        XCTAssertEqual(status, .completed, app.debugDescription)
        app.buttons["savePipeline"].tap()
        XCTAssertTrue(app.navigationBars["New Pipeline"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

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
        app.buttons["editFilenameTemplate"].tap()
        let clear = app.buttons["Clear template"]
        for _ in 0..<8 { if clear.isHittable { break }; app.swipeUp() }
        clear.tap()
        let date = app.buttons["addTemplate-documentDate"]
        for _ in 0..<8 { if date.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(date.isHittable)
        date.tap()
        let separator = app.buttons["addTemplate-underscore"]
        for _ in 0..<8 { if separator.isHittable { break }; app.swipeUp() }
        separator.tap()
        let word = app.buttons["addTemplate-word1"]
        for _ in 0..<8 { if word.isHittable { break }; app.swipeDown() }
        word.tap()
        let example = app.staticTexts["templateExample"]
        for _ in 0..<8 { if example.isHittable { break }; app.swipeUp() }
        let composerCapture = XCTAttachment(screenshot: app.screenshot())
        composerCapture.name = "Filename composer after three parts"
        composerCapture.lifetime = .keepAlways
        add(composerCapture)
        XCTAssertTrue(example.label.contains("2026-10-05_Telekom.pdf"), example.label)
        app.buttons["Done"].tap()
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
        app.launchEnvironment["PDFPIPE_UI_TEST_CONFIGURATION_SUITE"] = "com.kaps.pdfpipe.ui-tests.\(UUID().uuidString)"
        app.launch()
        let pipelineName = "Swipe " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["newPipeline"].waitForExistence(timeout: 10))
        app.buttons["newPipeline"].tap()
        let name = app.textFields["pipelineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + pipelineName)
        app.swipeUp() // Dismiss the keyboard before testing toggles at accessibility text sizes.
        let ocr = app.switches["enableOCR"]
        XCTAssertTrue(ocr.exists)
        XCTAssertTrue(app.switches["enableRename"].exists)
        tapSwitch(ocr)
        XCTAssertEqual(ocr.value as? String, "1")
        let skipExisting = app.switches["skipExistingText"]
        XCTAssertEqual(skipExisting.value as? String, "1")
        if !skipExisting.isHittable { app.swipeUp() }
        tapSwitch(skipExisting)
        let toggleCapture = XCTAttachment(screenshot: app.screenshot())
        toggleCapture.name = "OCR settings after toggle"
        toggleCapture.lifetime = .keepAlways
        add(toggleCapture)
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
        XCTAssertTrue(app.navigationBars["New Pipeline"].waitForNonExistence(timeout: 5))
        createPipeline(named: "Chooser alternative", in: app)
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
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "Choosing a pipeline should present the Files picker: \(app.debugDescription)")
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

    func testSolePipelineImportOpensFilesDirectly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PDFPIPE_UI_TEST_CONFIGURATION_SUITE"] = "com.kaps.pdfpipe.ui-tests.\(UUID().uuidString)"
        app.launch()
        let buildDate = app.staticTexts["buildDate"]
        XCTAssertTrue(buildDate.waitForExistence(timeout: 10))
        XCTAssertFalse(buildDate.label.contains("unavailable"), buildDate.label)
        createPipeline(named: "Only pipeline", in: app)
        app.buttons["importDocument"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "Abbrechen")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "A sole pipeline should open Files directly: \(app.debugDescription)")
        XCTAssertFalse(app.navigationBars["Choose a pipeline"].exists)
        cancel.tap()
        XCTAssertTrue(app.buttons["importDocument"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pipeline-", "Only pipeline")).firstMatch.exists)
    }

    private func createPipeline(named pipelineName: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["newPipeline"].waitForExistence(timeout: 10))
        app.buttons["newPipeline"].tap()
        let name = app.textFields["pipelineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + pipelineName)
        app.swipeUp()
        app.buttons["savePipeline"].tap()
        XCTAssertTrue(app.navigationBars["New Pipeline"].waitForNonExistence(timeout: 5))
    }

    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
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
        XCTAssertTrue(app.staticTexts["proposedFilename"].label.contains("document analysis"))
        XCTAssertTrue(app.buttons["runPipeline"].waitForExistence(timeout: 5))
        app.buttons["runPipeline"].tap()
        XCTAssertTrue(app.buttons["confirmFilename"].waitForExistence(timeout: 10))
        app.buttons["confirmFilename"].tap()
        XCTAssertTrue(app.textFields["resultFilename"].waitForExistence(timeout: 10))
        let resultFilename = try XCTUnwrap(app.textFields["resultFilename"].value as? String)
        app.buttons["sharePDF"].tap()
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
        XCTAssertTrue(extensionUI.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", resultFilename)).firstMatch.exists,
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
