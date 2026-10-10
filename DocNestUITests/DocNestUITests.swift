import AppKit
import XCTest

final class DocNestUITests: XCTestCase {
    private var appBundleIdentifier: String {
        Bundle(for: Self.self).object(forInfoDictionaryKey: "DocNestAppBundleIdentifier") as? String
            ?? "com.kaps.docnest"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningDocNestApplications()
        clearPersistedLibraryDefaults()
    }

    @MainActor
    func testApplicationLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testWelcomeOffersLibraryActionsWithoutInactivePanels() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["create-library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["open-library"].exists)
        XCTAssertFalse(app.buttons["import-documents"].exists)
        XCTAssertEqual(app.menuBars.menuBarItems.matching(identifier: "View").count, 1)
        captureScreenshot("Welcome — Light", app: app)
        app.terminate()
        app.launchEnvironment["DOCNEST_UI_WINDOW_WIDTH"] = "560"
        app.launchEnvironment["DOCNEST_UI_WINDOW_HEIGHT"] = "460"
        app.launchArguments += ["-appearanceMode", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["create-library"].waitForExistence(timeout: 10))
        captureScreenshot("Welcome — Dark", app: app)
        XCTAssertLessThan(app.windows.firstMatch.frame.width, 700)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["DocNest Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Library Open"].exists)
        captureScreenshot("Settings — No Library", app: app)
    }

    @MainActor
    func testEmptySearchAndBinExplainTheirContext() throws {
        let libraryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("docnestlibrary")
        defer { try? FileManager.default.removeItem(at: libraryURL) }
        try createLibraryFixture(at: libraryURL)
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-selectedLibraryPath", libraryURL.path]
        app.launch()
        XCTAssertTrue(waitForOpenLibraryRoot(in: app))
        XCTAssertTrue(app.buttons["Import Documents…"].exists)
        captureScreenshot("Empty Library", app: app)
        app.typeKey("f", modifierFlags: .command)
        app.typeText("unmatched-search")
        XCTAssertTrue(app.buttons["Clear Search"].waitForExistence(timeout: 5))
        app.buttons["Clear Search"].click()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bin,")).firstMatch.click()
        XCTAssertTrue(app.buttons["Show All Documents"].waitForExistence(timeout: 5))
        captureScreenshot("Empty Bin", app: app)
        app.buttons["Show All Documents"].click()
        XCTAssertTrue(app.buttons["Import Documents…"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func captureScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Optional visual audit of a synthetic library produced by Tools/create_review_fixtures.swift.
    @MainActor
    func testReviewFixtureLayouts() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["DOCNEST_REVIEW_FIXTURE"] else {
            throw XCTSkip("Set DOCNEST_REVIEW_FIXTURE to a disposable review library.")
        }
        let reviewRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: reviewRoot, withIntermediateDirectories: true)
        let libraryURL = reviewRoot.appendingPathComponent("Review Library.docnestlibrary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: fixturePath), to: libraryURL)
        defer { try? FileManager.default.removeItem(at: reviewRoot) }
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-selectedLibraryPath", libraryURL.path,
                                "-appearanceMode", "light"]
        let compactOnly = ProcessInfo.processInfo.environment["DOCNEST_REVIEW_COMPACT_ONLY"] == "1"
        if compactOnly {
            app.launchEnvironment["DOCNEST_UI_WINDOW_WIDTH"] = "960"
            app.launchEnvironment["DOCNEST_UI_WINDOW_HEIGHT"] = "700"
        }
        app.launch()
        XCTAssertTrue(waitForOpenLibraryRoot(in: app))
        if compactOnly {
            XCTAssertLessThan(app.windows.firstMatch.frame.width, 1100)
            captureScreenshot("Review — Compact", app: app)
            return
        }
        captureScreenshot("Review — Populated", app: app)
        let document = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Invoice October 2026")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        document.click()
        captureScreenshot("Review — Selected PDF", app: app)
        app.buttons["assign-labels"].click()
        XCTAssertTrue(app.textFields["label-picker-search"].waitForExistence(timeout: 5))
        captureScreenshot("Review — Label Popover", app: app)
        app.typeKey(.escape, modifierFlags: [])
        app.radioButtons["square.grid.2x2"].click()
        captureScreenshot("Review — Thumbnails", app: app)
        app.radioButtons["list.bullet"].click()
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Insurance Policy")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Insurance Policy")).firstMatch.waitForExistence(timeout: 5))
        captureScreenshot("Review — Search", app: app)
        app.searchFields.firstMatch.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        document.click()
        app.typeKey("d", modifierFlags: .control)
        captureScreenshot("Review — Inspector Hidden", app: app)
        app.typeKey("d", modifierFlags: .control)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["DocNest Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New Label"].exists)
        captureScreenshot("Review — Settings", app: app)
        app.buttons["New Label"].click()
        let labelName = app.textFields["Label name"]
        XCTAssertTrue(labelName.waitForExistence(timeout: 5))
        labelName.click()
        labelName.typeText("Review Test Label")
        captureScreenshot("Review — Label Editor", app: app)
        app.buttons["Create"].click()
        XCTAssertTrue(app.staticTexts["Review Test Label"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["-appearanceMode", "dark"]
        app.launch()
        XCTAssertTrue(waitForOpenLibraryRoot(in: app))
        document.click()
        captureScreenshot("Review — Dark", app: app)
    }

    @MainActor
    func testApplicationRestoresLastOpenedLibraryOnStartup() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Restored Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path]
        app.launch()

        XCTAssertTrue(
            waitForOpenLibraryRoot(in: app),
            "Expected the open-library root view to appear after restoring a library fixture"
        )
    }

    @MainActor
    func testOpenLibraryUsesOnlySystemSidebarToggle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Toolbar Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path]
        app.launch()

        XCTAssertTrue(
            waitForOpenLibraryRoot(in: app),
            "Expected the open-library root view to appear after restoring a library fixture"
        )
        XCTAssertFalse(
            app.buttons["Toggle Sidebar"].exists,
            "RootView should not add a second custom sidebar toggle button."
        )
    }

    @MainActor
    func testCommandFFocusesSearchFieldWhenLibraryIsOpen() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Search Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path]
        app.launch()

        XCTAssertTrue(
            waitForOpenLibraryRoot(in: app),
            "Expected the open-library root view to appear after restoring a library fixture"
        )

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("invoice")

        XCTAssertEqual(searchField.value as? String, "invoice")
    }

    @MainActor
    func testOpenLibraryUsesNativeImportAndAnchoredLabelAssignmentActions() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Label Actions Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path,
                                "-uiTestSeedAssignedLocationName", "Label Test Shelf"]
        app.launch()

        XCTAssertTrue(waitForOpenLibraryRoot(in: app))

        let importButton = app.buttons["import-documents"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        XCTAssertEqual(importButton.label, "Import…")

        let seededDocument = app.staticTexts["UI Test Assigned Document: Label Test Shelf"].firstMatch
        XCTAssertTrue(seededDocument.waitForExistence(timeout: 10))
        seededDocument.click()

        let assignLabelsButton = app.buttons["assign-labels"]
        XCTAssertTrue(assignLabelsButton.waitForExistence(timeout: 10))
        XCTAssertTrue(assignLabelsButton.isEnabled)
        assignLabelsButton.click()

        XCTAssertTrue(
            app.textFields["label-picker-search"].waitForExistence(timeout: 10),
            "Expected label assignment to open from its toolbar popover"
        )
    }

    @MainActor
    func testLocationsCanBeCreatedRenamedAndDeletedFromSidebar() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Locations Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path]
        app.launch()

        XCTAssertTrue(
            waitForOpenLibraryRoot(in: app),
            "Expected the open-library root view to appear after restoring a library fixture"
        )

        let addLocationButton = app.buttons["location-add-button"]
        XCTAssertTrue(addLocationButton.waitForExistence(timeout: 10))
        addLocationButton.click()

        let createSheet = app.sheets.firstMatch
        XCTAssertTrue(createSheet.waitForExistence(timeout: 10))

        let nameField = createSheet.textFields["location-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        let originalLocationName = "Archive Box"
        nameField.typeText(originalLocationName)
        createSheet.buttons["Create"].click()
        XCTAssertTrue(waitForNonExistence(createSheet, timeout: 10))

        let createdLocationLabel = app.staticTexts["Archive Box"]
        XCTAssertTrue(createdLocationLabel.waitForExistence(timeout: 10))
        let editButton = app.buttons["location-edit-Archive Box"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10))
        editButton.click()

        let editSheet = app.sheets.firstMatch
        XCTAssertTrue(editSheet.waitForExistence(timeout: 10))

        let renamedNameField = editSheet.textFields["location-name-field"]
        XCTAssertTrue(renamedNameField.waitForExistence(timeout: 10))
        renamedNameField.click()
        app.typeKey("a", modifierFlags: .command)
        renamedNameField.typeText("Shelf A")
        XCTAssertEqual(renamedNameField.value as? String, "Shelf A")
        editSheet.buttons["Save"].click()
        XCTAssertTrue(waitForNonExistence(editSheet, timeout: 10))

        let renamedLocationLabel = app.staticTexts["Shelf A"]
        XCTAssertTrue(renamedLocationLabel.waitForExistence(timeout: 10))
        let deleteButton = app.buttons["location-delete-Shelf A"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        deleteButton.click()

        XCTAssertTrue(waitForNonExistence(app.staticTexts["Shelf A"], timeout: 10))
    }

    @MainActor
    func testDeletingLocationWithAssignedDocumentRequiresConfirmation() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Assigned Location Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try createLibraryFixture(at: libraryURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-selectedLibraryPath", libraryURL.path,
                                "-uiTestSeedAssignedLocationName", "Archive Shelf"]
        app.launch()

        XCTAssertTrue(
            waitForOpenLibraryRoot(in: app),
            "Expected the open-library root view to appear after restoring a library fixture"
        )

        let locationLabel = app.staticTexts["Archive Shelf"]
        XCTAssertTrue(locationLabel.waitForExistence(timeout: 10))

        let deleteButton = app.buttons["location-delete-Archive Shelf"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        deleteButton.click()

        let confirmationSheet = app.sheets.firstMatch
        XCTAssertTrue(confirmationSheet.waitForExistence(timeout: 10))

        let cancelButton = confirmationSheet.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10))
        cancelButton.click()
        XCTAssertTrue(waitForNonExistence(confirmationSheet, timeout: 10))

        XCTAssertTrue(locationLabel.waitForExistence(timeout: 10))

        deleteButton.click()

        XCTAssertTrue(confirmationSheet.waitForExistence(timeout: 10))
        let confirmDeleteButton = confirmationSheet.buttons["Delete Location"]
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 10))
        confirmDeleteButton.click()

        XCTAssertTrue(waitForNonExistence(app.staticTexts["Archive Shelf"], timeout: 10))
    }

    private func createLibraryFixture(at libraryURL: URL) throws {
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let requiredDirectories = ["Metadata", "Originals", "Previews", "LocationPhotos", "Diagnostics"]
        for directory in requiredDirectories {
            try FileManager.default.createDirectory(
                at: libraryURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let manifest = """
        {
          "createdAt" : "2026-03-10T12:00:00Z",
          "formatVersion" : 3
        }
        """

        try manifest.write(
            to: libraryURL.appendingPathComponent("Metadata", isDirectory: true).appendingPathComponent("library.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func terminateRunningDocNestApplications() {
        let deadline = Date().addingTimeInterval(5)

        while true {
            let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier)

            if runningApplications.isEmpty {
                return
            }

            runningApplications.forEach { application in
                _ = application.forceTerminate()
            }

            guard Date() < deadline else {
                return
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func clearPersistedLibraryDefaults() {
        guard let defaults = UserDefaults(suiteName: appBundleIdentifier) else { return }
        defaults.removeObject(forKey: "selectedLibraryPath")
        defaults.removeObject(forKey: "selectedLibraryBookmark")
        defaults.synchronize()
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter(delegate: self).wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForOpenLibraryRoot(in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let found = app.buttons["import-documents"].waitForExistence(timeout: timeout)
        if !found {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Missing library root — accessibility tree"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        return found
    }

}
