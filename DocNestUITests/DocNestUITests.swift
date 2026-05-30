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
            app.otherElements[openLibraryRootIdentifier].waitForExistence(timeout: 10),
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
            app.otherElements[openLibraryRootIdentifier].waitForExistence(timeout: 10),
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
            app.otherElements[openLibraryRootIdentifier].waitForExistence(timeout: 10),
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
            app.otherElements[openLibraryRootIdentifier].waitForExistence(timeout: 10),
            "Expected the open-library root view to appear after restoring a library fixture"
        )

        let addLocationButton = app.buttons["location-add-button"]
        XCTAssertTrue(addLocationButton.waitForExistence(timeout: 10))
        addLocationButton.click()

        let nameField = app.textFields["location-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeText("Archive Box")
        app.buttons["Create"].click()

        let createdRow = app.otherElements["location-row-Archive Box"]
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10))

        let createdActionsButton = app.buttons["location-actions-Archive Box"]
        XCTAssertTrue(createdActionsButton.waitForExistence(timeout: 10))
        createdActionsButton.click()
        app.menuItems["Edit Location"].click()

        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        nameField.typeText("Shelf A")
        app.buttons["Save"].click()

        let renamedRow = app.otherElements["location-row-Shelf A"]
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 10))

        let renamedActionsButton = app.buttons["location-actions-Shelf A"]
        XCTAssertTrue(renamedActionsButton.waitForExistence(timeout: 10))
        renamedActionsButton.click()
        app.menuItems["Delete Location"].click()

        XCTAssertTrue(waitForNonExistence(renamedRow, timeout: 10))
    }

    private func createLibraryFixture(at libraryURL: URL) throws {
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let requiredDirectories = ["Metadata", "Originals", "Previews", "Diagnostics"]
        for directory in requiredDirectories {
            try FileManager.default.createDirectory(
                at: libraryURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let manifest = """
        {
          "createdAt" : "2026-03-10T12:00:00Z",
          "formatVersion" : 1
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
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

}
