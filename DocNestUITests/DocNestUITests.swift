import AppKit
import XCTest

final class DocNestUITests: XCTestCase {
    private let appBundleIdentifier = "com.kaps.docnest"
    private let openLibraryRootIdentifier = "library-open-root"

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
          "formatVersion" : 2
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
        app.descendants(matching: .any)[openLibraryRootIdentifier].waitForExistence(timeout: timeout)
    }

}
