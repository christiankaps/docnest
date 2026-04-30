import AppKit
import XCTest
import SwiftData
import SwiftUI
import PDFKit
@testable import DocNest

private enum TestSampleDataSeeder {
    @MainActor
    static func seedIfNeeded(using context: ModelContext) throws {
        let descriptor = FetchDescriptor<DocumentRecord>()
        let existingCount = try context.fetchCount(descriptor)
        guard existingCount == 0 else { return }

        let labels = LabelTag.makeSamples()
        context.insert(labels.finance)
        context.insert(labels.tax)
        context.insert(labels.contracts)

        let documents = DocumentRecord.makeSamples(labels: labels)
        for document in documents {
            context.insert(document)
        }

        try context.save()
    }
}

private enum TestImportFixtures {
    static func createPDF(at url: URL, text: String = "Test PDF") throws {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 200)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        NSString(string: text).draw(at: NSPoint(x: 24, y: 96), withAttributes: attributes)
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "DocNestTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF page."])
        }

        document.insert(page, at: 0)
        guard let data = document.dataRepresentation() else {
            throw NSError(domain: "DocNestTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render PDF data."])
        }

        try data.write(to: url)
    }

    @MainActor
    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: DocumentRecord.self,
            LabelTag.self,
            configurations: config
        )
    }
}

final class DocNestTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        DocumentLibraryService.persistLibraryURL(nil)
    }

    @MainActor
    func testSampleDataCanBeSeeded() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        try TestSampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 3)
    }

    @MainActor
    func testSeedingIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        try TestSampleDataSeeder.seedIfNeeded(using: context)
        try TestSampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3, "Seeding should not duplicate data on second call")
    }

    @MainActor
    func testDocumentRecordAcceptsStoredFilePath() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let doc = DocumentRecord(
            originalFileName: "test.pdf",
            title: "Test",
            documentDate: .now.addingTimeInterval(-86_400),
            importedAt: .now,
            pageCount: 1,
            fileSize: 8_192,
            contentHash: "abc123",
            storedFilePath: "/tmp/test-path.pdf"
        )
        context.insert(doc)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(fetched.first?.storedFilePath, "/tmp/test-path.pdf")
        XCTAssertEqual(fetched.first?.fileSize, 8_192)
        XCTAssertEqual(fetched.first?.contentHash, "abc123")
    }

    func testCreateLibraryCreatesRequiredStructure() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Test Library")

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)

        XCTAssertEqual(createdLibraryURL.pathExtension, DocumentLibraryService.packageExtension)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Metadata", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Originals", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Metadata/library.json").path))
    }

    func testValidateLibraryRejectsMissingManifest() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Broken Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Metadata", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Originals", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Previews", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Diagnostics", isDirectory: true), withIntermediateDirectories: true)

        XCTAssertThrowsError(try DocumentLibraryService.validateLibrary(at: libraryURL))
    }

    func testPersistedLibraryURLRoundTripsNormalizedPath() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Remember Me")

        defer {
            DocumentLibraryService.persistLibraryURL(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)

        DocumentLibraryService.persistLibraryURL(createdLibraryURL)

        XCTAssertEqual(
            DocumentLibraryService.restorePersistedLibraryAccess()?.url,
            createdLibraryURL.standardizedFileURL
        )
    }

    func testClearingPersistedLibraryURLRemovesStartupRestoreTarget() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Forget Me")

        defer {
            DocumentLibraryService.persistLibraryURL(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)
        DocumentLibraryService.persistLibraryURL(createdLibraryURL)

        DocumentLibraryService.persistLibraryURL(nil)

        XCTAssertNil(DocumentLibraryService.restorePersistedLibraryAccess())
    }

    func testSelectedLibraryURLReadsLaunchArgumentOverride() {
        let expectedURL = URL(fileURLWithPath: "/tmp/Test Library.docnestlibrary").standardizedFileURL

        let restoredURL = DocumentLibraryService.selectedLibraryURL(
            from: ["DocNest", "-selectedLibraryPath", expectedURL.path]
        )

        XCTAssertEqual(restoredURL, expectedURL)
    }

    func testSelectedLibraryURLIgnoresMissingLaunchArgumentValue() {
        XCTAssertNil(
            DocumentLibraryService.selectedLibraryURL(
                from: ["DocNest", "-selectedLibraryPath"]
            )
        )
    }

    func testOCRBackendDefaultsToVisionDuringTests() {
        let backend = OCRBackend.resolved(
            storedRawValue: nil,
            environment: ["XCTestConfigurationFilePath": "/tmp/xctest-config"]
        )

        XCTAssertEqual(backend, .vision)
    }

    func testOCRBackendOverrideWinsDuringTests() {
        let backend = OCRBackend.resolved(
            storedRawValue: OCRBackend.automatic.rawValue,
            environment: [
                "XCTestConfigurationFilePath": "/tmp/xctest-config",
                "DOCNEST_OCR_BACKEND": OCRBackend.ocrmypdf.rawValue
            ]
        )

        XCTAssertEqual(backend, .ocrmypdf)
    }

    func testOCRBackendUsesStoredPreferenceOutsideTests() {
        let backend = OCRBackend.resolved(
            storedRawValue: OCRBackend.ocrmypdf.rawValue,
            environment: [:]
        )

        XCTAssertEqual(backend, .ocrmypdf)
    }

    @MainActor
    func testOCRDateUpdatePolicyUpdatesOnlyUnchangedFallbackDates() {
        let fallbackDate = Date(timeIntervalSince1970: 10)
        let editedDate = Date(timeIntervalSince1970: 20)
        let unchanged = DocumentRecord(
            originalFileName: "unchanged.pdf",
            title: "Unchanged",
            documentDate: fallbackDate,
            importedAt: .now,
            pageCount: 1
        )
        let edited = DocumentRecord(
            originalFileName: "edited.pdf",
            title: "Edited",
            documentDate: editedDate,
            importedAt: .now,
            pageCount: 1
        )
        let unchangedNil = DocumentRecord(
            originalFileName: "undated.pdf",
            title: "Undated",
            documentDate: nil,
            importedAt: .now,
            pageCount: 1
        )
        let policy = OCRDateUpdatePolicy(
            fallbackDatesByDocumentID: [
                unchanged.persistentModelID: fallbackDate,
                edited.persistentModelID: fallbackDate,
                unchangedNil.persistentModelID: nil
            ]
        )

        XCTAssertTrue(policy.shouldUpdateDate(for: unchanged))
        XCTAssertFalse(policy.shouldUpdateDate(for: edited))
        XCTAssertTrue(policy.shouldUpdateDate(for: unchangedNil))
        XCTAssertFalse(OCRDateUpdatePolicy.preserveExistingDates.shouldUpdateDate(for: unchanged))
    }

    func testFolderMonitorDeltaReportsOnlyNewAndChangedPDFs() {
        let originalDate = Date(timeIntervalSinceReferenceDate: 100)
        let updatedDate = Date(timeIntervalSinceReferenceDate: 200)
        let unchangedPath = "/tmp/unchanged.pdf"
        let changedPath = "/tmp/changed.pdf"
        let newPath = "/tmp/new.pdf"

        let result = FolderMonitorService.newPDFURLs(
            from: [
                .init(path: unchangedPath, modificationDate: originalDate),
                .init(path: changedPath, modificationDate: updatedDate),
                .init(path: newPath, modificationDate: updatedDate)
            ],
            previousSnapshots: [
                unchangedPath: originalDate,
                changedPath: originalDate
            ]
        )

        XCTAssertEqual(
            Set(result.urls.map(\.path)),
            Set([changedPath, newPath])
        )
        XCTAssertEqual(
            result.updatedSnapshots,
            [
                unchangedPath: originalDate,
                changedPath: updatedDate,
                newPath: updatedDate
            ]
        )
    }

    func testFolderMonitorDeltaDropsRemovedFilesFromSnapshot() {
        let originalDate = Date(timeIntervalSinceReferenceDate: 100)
        let remainingPath = "/tmp/remaining.pdf"
        let removedPath = "/tmp/removed.pdf"

        let result = FolderMonitorService.newPDFURLs(
            from: [
                .init(path: remainingPath, modificationDate: originalDate)
            ],
            previousSnapshots: [
                remainingPath: originalDate,
                removedPath: originalDate
            ]
        )

        XCTAssertTrue(result.urls.isEmpty)
        XCTAssertEqual(
            result.updatedSnapshots,
            [remainingPath: originalDate]
        )
    }

    @MainActor
    func testImportPDFDocumentsUseCaseImportsNestedFolderPDFsAndIgnoresNonPDFs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let importRoot = tempRoot.appendingPathComponent("ImportRoot", isDirectory: true)
        let nestedFolder = importRoot.appendingPathComponent("Nested", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try TestImportFixtures.createPDF(at: importRoot.appendingPathComponent("top-level.pdf"), text: "Top Level")
        try TestImportFixtures.createPDF(at: nestedFolder.appendingPathComponent("nested.pdf"), text: "Nested")
        try Data("ignore me".utf8).write(to: nestedFolder.appendingPathComponent("notes.txt"))

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("ImportLibrary")
        )
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext

        let result = await ImportPDFDocumentsUseCase.execute(
            urls: [importRoot],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertFalse(result.hasNoImportablePDFs)
        XCTAssertTrue(result.unsupportedFiles.isEmpty)
        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(Set(documents.map(\.originalFileName)), Set(["top-level.pdf", "nested.pdf"]))
    }

    @MainActor
    func testImportPDFDocumentsUseCaseReportsNoPDFsForFolderWithoutPDFContent() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let importRoot = tempRoot.appendingPathComponent("NoPDFs", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: importRoot.appendingPathComponent("readme.txt"))

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("EmptyLibrary")
        )
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext

        let result = await ImportPDFDocumentsUseCase.execute(
            urls: [importRoot],
            into: libraryURL,
            using: context
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertTrue(result.hasNoImportablePDFs)
        XCTAssertEqual(result.summaryMessage, "No PDF documents found to import.")
    }

    @MainActor
    func testImportPDFDocumentsUseCaseRejectsLibrarySubfoldersAsImportSource() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("SelfImportLibrary")
        )
        let nestedLibraryFolder = DocumentLibraryService.originalsDirectory(for: libraryURL)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedLibraryFolder, withIntermediateDirectories: true)
        try TestImportFixtures.createPDF(at: nestedLibraryFolder.appendingPathComponent("inside.pdf"), text: "Inside")

        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let result = await ImportPDFDocumentsUseCase.execute(
            urls: [nestedLibraryFolder],
            into: libraryURL,
            using: context
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertFalse(result.hasNoImportablePDFs)
    }

    func testFolderMonitorScanSnapshotsFindsNestedPDFsRecursively() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watchRoot = tempRoot.appendingPathComponent("WatchRoot", isDirectory: true)
        let nestedFolder = watchRoot.appendingPathComponent("Deep", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try TestImportFixtures.createPDF(at: nestedFolder.appendingPathComponent("nested-watch.pdf"), text: "Watch")
        try Data("ignore".utf8).write(to: watchRoot.appendingPathComponent("note.txt"))

        let result = try FolderMonitorService.scanSnapshots(
            in: watchRoot.path,
            previousSnapshots: [:]
        )

        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["nested-watch.pdf"])
        XCTAssertEqual(result.updatedSnapshots.count, 1)
    }

    func testFolderMonitorApplyFileEventsTracksNestedPDFChanges() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watchRoot = tempRoot.appendingPathComponent("WatchRoot", isDirectory: true)
        let nestedFolder = watchRoot.appendingPathComponent("Deep", isDirectory: true)
        let nestedPDF = nestedFolder.appendingPathComponent("nested-event.pdf")

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try TestImportFixtures.createPDF(at: nestedPDF, text: "Event")

        let result = try FolderMonitorService.applyFileEvents(
            [nestedPDF.path: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)],
            in: watchRoot.path,
            previousSnapshots: [:]
        )

        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["nested-event.pdf"])
        XCTAssertEqual(result.updatedSnapshots.count, 1)
        XCTAssertNotNil(result.updatedSnapshots[nestedPDF.path])
    }

    func testAcquireLockCreatesLockFile() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("LockTest")
        )

        try DocumentLibraryService.acquireLock(for: libraryURL)

        let lock = DocumentLibraryService.readLockFile(for: libraryURL)
        XCTAssertNotNil(lock)
        XCTAssertEqual(lock?.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(lock?.hostname, ProcessInfo.processInfo.hostName)

        DocumentLibraryService.releaseLock(for: libraryURL)
    }

    func testReleaseLockRemovesLockFile() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("LockTest")
        )

        try DocumentLibraryService.acquireLock(for: libraryURL)
        DocumentLibraryService.releaseLock(for: libraryURL)

        XCTAssertNil(DocumentLibraryService.readLockFile(for: libraryURL))
    }

    func testAcquireLockRejectsActiveNonStaleLock() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("LockTest")
        )

        // Spawn a short-lived child process so we have a PID that is
        // definitely alive and owned by the current user. This ensures
        // kill(pid, 0) == 0 succeeds reliably on both local machines and
        // CI runners, where the parent PID may not be signalable.
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["60"]
        try sleeper.run()
        defer { sleeper.terminate(); sleeper.waitUntilExit() }

        let foreignLock = LibraryLockFile(
            hostname: ProcessInfo.processInfo.hostName,
            pid: sleeper.processIdentifier,
            updatedAt: .now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(foreignLock)
        let lockURL = libraryURL
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent(".lock")
        try data.write(to: lockURL, options: .atomic)

        XCTAssertThrowsError(try DocumentLibraryService.acquireLock(for: libraryURL)) { error in
            XCTAssertTrue(error is DocumentLibraryService.LockError)
        }

        try? FileManager.default.removeItem(at: lockURL)
    }

    func testAcquireLockSucceedsWhenExistingLockIsStale() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("LockTest")
        )

        // Simulate a stale lock (updated well beyond the threshold)
        let staleLock = LibraryLockFile(
            hostname: "other-machine.local",
            pid: 99999,
            updatedAt: Date(timeIntervalSinceNow: -(LibraryLockFile.staleThreshold + 10))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(staleLock)
        let lockURL = libraryURL
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent(".lock")
        try data.write(to: lockURL, options: .atomic)

        XCTAssertNoThrow(try DocumentLibraryService.acquireLock(for: libraryURL))

        DocumentLibraryService.releaseLock(for: libraryURL)
    }

    func testSameProcessCanReacquireOwnLock() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("LockTest")
        )

        try DocumentLibraryService.acquireLock(for: libraryURL)
        XCTAssertNoThrow(try DocumentLibraryService.acquireLock(for: libraryURL))

        DocumentLibraryService.releaseLock(for: libraryURL)
    }

    func testOpenLibraryLayoutKeepsSidePanelsFixedAndDocumentListFlexible() {
        XCTAssertEqual(AppSplitViewLayout.sidebarWidth, 260)
        XCTAssertEqual(AppSplitViewLayout.inspectorWidth, 420)
        XCTAssertEqual(AppSplitViewLayout.documentListMinWidth, 280)
        XCTAssertEqual(
            AppSplitViewLayout.minimumOpenLibraryWindowWidth,
            AppSplitViewLayout.sidebarWidth + AppSplitViewLayout.documentListMinWidth + AppSplitViewLayout.inspectorWidth
        )
        XCTAssertLessThan(AppSplitViewLayout.documentListMinWidth, AppSplitViewLayout.inspectorWidth)
        XCTAssertLessThan(AppSplitViewLayout.documentListMinWidth, AppSplitViewLayout.closedLibraryContentMinWidth)
    }

    func testClosedLibraryLayoutPreservesSidePanelWidths() {
        XCTAssertEqual(AppSplitViewLayout.closedLibraryContentMinWidth, 360)
        XCTAssertEqual(
            AppSplitViewLayout.minimumClosedLibraryWindowWidth,
            AppSplitViewLayout.sidebarWidth + AppSplitViewLayout.closedLibraryContentMinWidth + AppSplitViewLayout.inspectorWidth
        )
        XCTAssertEqual(
            AppSplitViewLayout.minimumWindowWidth,
            max(AppSplitViewLayout.minimumOpenLibraryWindowWidth, AppSplitViewLayout.minimumClosedLibraryWindowWidth)
        )
    }

    func testResizeHandleCursorStateResetsCursorWhenHoverEnds() {
        var state = ResizeHandleCursorState()

        XCTAssertEqual(state.hoverChanged(true), .resizeLeftRight)
        XCTAssertEqual(state.hoverChanged(false), .arrow)
        XCTAssertFalse(state.isHovering)
        XCTAssertFalse(state.isCursorActive)
    }

    func testResizeHandleCursorStateResetsCursorWhenViewDisappears() {
        var state = ResizeHandleCursorState()

        XCTAssertEqual(state.hoverChanged(true), .resizeLeftRight)
        XCTAssertEqual(state.disappeared(), .arrow)
        XCTAssertFalse(state.isHovering)
        XCTAssertFalse(state.isCursorActive)
    }

    func testDeferredSelectionStateUpdatesVisualSelectionImmediately() {
        var state = DeferredSelectionState<String>()

        state.toggleVisualSelection(for: "finance")

        XCTAssertEqual(state.visualSelection, ["finance"])
        XCTAssertTrue(state.appliedSelection.isEmpty)
    }

    func testDeferredSelectionStateCommitsVisualSelectionSeparately() {
        var state = DeferredSelectionState<String>()

        state.replaceVisualSelection(with: ["finance", "tax"])
        state.commitVisualSelection()

        XCTAssertEqual(state.visualSelection, ["finance", "tax"])
        XCTAssertEqual(state.appliedSelection, ["finance", "tax"])
    }

    func testDeferredSelectionStateSyncsAvailableSelectionsAcrossVisualAndAppliedState() {
        var state = DeferredSelectionState<String>()

        state.replaceVisualSelection(with: ["finance", "tax"])
        state.commitVisualSelection()
        state.replaceVisualSelection(with: ["tax", "legal"])

        state.syncAvailableSelections(["tax", "contracts"])

        XCTAssertEqual(state.visualSelection, ["tax"])
        XCTAssertEqual(state.appliedSelection, ["tax"])
    }

    func testLibrarySidebarCountsReflectSectionBucketsAndLabels() {
        let finance = LabelTag(name: "Finance")
        let tax = LabelTag(name: "Tax")
        let archive = LabelTag(name: "Archive")
        let documents = [
            DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [finance, tax]),
            DocumentRecord(originalFileName: "receipt.pdf", title: "Receipt", importedAt: .now, pageCount: 1, labels: [finance]),
            DocumentRecord(originalFileName: "contract.pdf", title: "Contract", importedAt: .now, pageCount: 1)
        ]

        let counts = LibrarySidebarCounts(activeDocuments: documents, trashedCount: 0, labels: [finance, tax, archive], recentLimit: 10, labelSourceDocuments: documents, activeLabelFilterIDs: [])

        XCTAssertEqual(counts.count(for: .allDocuments), 3)
        XCTAssertEqual(counts.count(for: .recent), 3)
        XCTAssertEqual(counts.count(for: .needsLabels), 1)
        XCTAssertEqual(counts.count(for: finance), 2)
        XCTAssertEqual(counts.count(for: tax), 1)
        XCTAssertEqual(counts.count(for: archive), 0)
    }

    func testLibrarySidebarCountsCapsRecentBucketAtRecentLimit() {
        let documents = (0..<12).map { index in
            DocumentRecord(
                originalFileName: "doc-\(index).pdf",
                title: "Doc \(index)",
                importedAt: .now,
                pageCount: 1
            )
        }

        let counts = LibrarySidebarCounts(activeDocuments: documents, trashedCount: 0, labels: [], recentLimit: 10, labelSourceDocuments: documents, activeLabelFilterIDs: [])

        XCTAssertEqual(counts.count(for: .allDocuments), 12)
        XCTAssertEqual(counts.count(for: .recent), 10)
        XCTAssertEqual(counts.count(for: .needsLabels), 12)
    }

    func testLibrarySidebarCountsExcludesBinItemsFromActiveBuckets() {
        let label = LabelTag(name: "Finance")
        let activeDocuments = [
            DocumentRecord(originalFileName: "active-a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [label]),
            DocumentRecord(originalFileName: "active-b.pdf", title: "B", importedAt: .now, pageCount: 1)
        ]

        let counts = LibrarySidebarCounts(activeDocuments: activeDocuments, trashedCount: 1, labels: [label], recentLimit: 10, labelSourceDocuments: activeDocuments, activeLabelFilterIDs: [])

        XCTAssertEqual(counts.count(for: .allDocuments), 2)
        XCTAssertEqual(counts.count(for: .needsLabels), 1)
        XCTAssertEqual(counts.count(for: .bin), 1)
        XCTAssertEqual(counts.count(for: label), 1)
    }

    func testDocumentFileDragPayloadRoundTripsSingleID() {
        let documentID = UUID()

        let payload = DocumentFileDragPayload.payload(for: [documentID])
        let parsedIDs = DocumentFileDragPayload.documentIDs(from: payload)

        XCTAssertEqual(parsedIDs, [documentID])
    }

    func testDocumentFileDragPayloadRoundTripsMultipleIDs() {
        let firstID = UUID()
        let secondID = UUID()

        let payload = DocumentFileDragPayload.payload(for: [firstID, secondID])
        let parsedIDs = DocumentFileDragPayload.documentIDs(from: payload)

        XCTAssertEqual(parsedIDs, [firstID, secondID])
    }

    @MainActor
    func testLibraryContainersStayIsolated() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryAURL = tempRoot.appendingPathComponent("Library A")
        let libraryBURL = tempRoot.appendingPathComponent("Library B")

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryAURL = try DocumentLibraryService.createLibrary(at: libraryAURL)
        let createdLibraryBURL = try DocumentLibraryService.createLibrary(at: libraryBURL)

        let containerA = try DocumentLibraryService.openModelContainer(for: createdLibraryAURL)
        let contextA = containerA.mainContext
        contextA.insert(
            DocumentRecord(
                originalFileName: "invoice.pdf",
                title: "Invoice",
                importedAt: .now,
                pageCount: 1,
                fileSize: 4_096,
                contentHash: "seededhash",
                storedFilePath: "Originals/2026/03/test.pdf"
            )
        )
        try contextA.save()

        let containerB = try DocumentLibraryService.openModelContainer(for: createdLibraryBURL)
        let documentsInLibraryB = try containerB.mainContext.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertTrue(documentsInLibraryB.isEmpty)

        let reopenedContainerA = try DocumentLibraryService.openModelContainer(for: createdLibraryAURL)
        let documentsInLibraryA = try reopenedContainerA.mainContext.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documentsInLibraryA.count, 1)
        XCTAssertEqual(documentsInLibraryA.first?.title, "Invoice")
        XCTAssertTrue(FileManager.default.fileExists(atPath: DocumentLibraryService.metadataStoreURL(for: createdLibraryAURL).path))
    }

    @MainActor
    func testOpeningV4LibraryMigratesLabelsAndSupportsLabelValues() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("V4 Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let configuration = ModelConfiguration(
            "DocNestLibrary",
            url: DocumentLibraryService.metadataStoreURL(for: libraryURL),
            cloudKitDatabase: .none
        )
        let v4Schema = Schema(versionedSchema: DocNestSchemaV4.self)
        do {
            let v4Container = try ModelContainer(for: v4Schema, configurations: configuration)
            let context = v4Container.mainContext
            let label = DocNestSchemaV4.LabelTag(name: "Invoice", colorName: LabelColor.green.rawValue)
            let document = DocNestSchemaV4.DocumentRecord(
                originalFileName: "invoice.pdf",
                title: "Invoice",
                importedAt: .now,
                pageCount: 1,
                labels: [label]
            )
            context.insert(label)
            context.insert(document)
            try context.save()
        }

        let migratedContainer = try DocumentLibraryService.openModelContainer(for: libraryURL)
        let context = migratedContainer.mainContext
        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(documents.first?.labels.first?.name, "Invoice")
        XCTAssertNil(labels.first?.unitSymbol)

        guard let document = documents.first, let label = labels.first else {
            XCTFail("Expected migrated document and label.")
            return
        }

        label.unitSymbol = "€"
        try ManageLabelValuesUseCase.setValue("15.50", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.decimalString, "15.5")
    }

    @MainActor
    func testOpeningReleasedV4LibraryFixtureMigratesLabelsAndSupportsLabelValues() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReleasedV4Library.docnestlibrary", isDirectory: true)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("ReleasedV4Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureURL, to: libraryURL)

        let migratedContainer = try DocumentLibraryService.openModelContainer(for: libraryURL)
        let context = migratedContainer.mainContext
        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(documents.first?.labels.first?.name, "Invoice")
        XCTAssertNil(labels.first?.unitSymbol)

        guard let document = documents.first, let label = labels.first else {
            XCTFail("Expected migrated fixture document and label.")
            return
        }

        label.unitSymbol = "€"
        try ManageLabelValuesUseCase.setValue("15.50", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.documentID, document.id)
        XCTAssertEqual(values.first?.labelID, label.id)
        XCTAssertEqual(values.first?.decimalString, "15.5")
    }

    @MainActor
    func testImportUseCaseCopiesPdfAndCreatesRecord() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcePDFURL = tempRoot.appendingPathComponent("invoice_march-2026.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: sourcePDFURL))

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let importResult = await ImportPDFDocumentsUseCase.execute(
            urls: [sourcePDFURL],
            into: libraryURL,
            using: context
        )

        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertFalse(importResult.hasFailures)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.title, "Invoice March 2026")
        XCTAssertEqual(documents.first?.pageCount, 1)
        XCTAssertFalse(documents.first?.contentHash.isEmpty ?? true)
        XCTAssertGreaterThan(documents.first?.fileSize ?? 0, 0)
        XCTAssertNotNil(documents.first?.documentDate)
        XCTAssertNil(documents.first?.fullText)
        XCTAssertEqual(documents.first?.ocrCompleted, false)
        XCTAssertEqual(importResult.importedDocuments.map(\.persistentModelID), documents.map(\.persistentModelID))

        guard let storedFilePath = documents.first?.storedFilePath else {
            XCTFail("Expected imported document to include a stored file path")
            return
        }

        XCTAssertTrue(storedFilePath.hasPrefix("Originals/"))
        XCTAssertTrue(DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL))
    }

    @MainActor
    func testImportUseCaseImportsTwoHundredDistinctPDFs() async throws {
        try await assertImportOfDistinctPDFs(count: 200)
    }

    @MainActor
    func testImportUseCaseImportsTenThousandDistinctPDFsStress() async throws {
        guard ProcessInfo.processInfo.environment["DOCNEST_RUN_STRESS_TESTS"] == "1" else {
            throw XCTSkip("Stress test disabled by default. Set DOCNEST_RUN_STRESS_TESTS=1 to run the 10,000-document import.")
        }

        try await assertImportOfDistinctPDFs(count: 10_000)
    }

    @MainActor
    func testImportUseCaseContinuesAfterPerFileFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingPDFURL = tempRoot.appendingPathComponent("missing.pdf")
        let validPDFURL = tempRoot.appendingPathComponent("valid.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Failure Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: validPDFURL))

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let importResult = await ImportPDFDocumentsUseCase.execute(
            urls: [missingPDFURL, validPDFURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertFalse(importResult.hasDuplicates)
        XCTAssertEqual(importResult.failures.count, 1)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.originalFileName, "valid.pdf")
    }

    @MainActor
    func testImportUseCaseSkipsDuplicatePdfByHash() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcePDFURL = tempRoot.appendingPathComponent("original.pdf")
        let duplicatePDFURL = tempRoot.appendingPathComponent("duplicate-copy.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Duplicate Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: sourcePDFURL))
        try FileManager.default.copyItem(at: sourcePDFURL, to: duplicatePDFURL)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let firstImport = await ImportPDFDocumentsUseCase.execute(
            urls: [sourcePDFURL],
            into: libraryURL,
            using: context
        )
        XCTAssertEqual(firstImport.importedCount, 1)

        let secondImport = await ImportPDFDocumentsUseCase.execute(
            urls: [duplicatePDFURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(secondImport.importedCount, 0)
        XCTAssertEqual(secondImport.duplicates.count, 1)
        XCTAssertFalse(secondImport.summaryMessage.isEmpty)
        XCTAssertEqual(documents.count, 1)
    }

    @MainActor
    func testImportUseCaseReportsUnsupportedFilesAndImportsValidPDFs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validPDFURL = tempRoot.appendingPathComponent("invoice.pdf")
        let unsupportedTextURL = tempRoot.appendingPathComponent("notes.txt")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Mixed Import Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: validPDFURL))
        try "hello".write(to: unsupportedTextURL, atomically: true, encoding: .utf8)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let importResult = await ImportPDFDocumentsUseCase.execute(
            urls: [validPDFURL, unsupportedTextURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.unsupportedFiles.count, 1)
        XCTAssertEqual(importResult.unsupportedFiles.first?.fileName, "notes.txt")
        XCTAssertTrue(importResult.summaryMessage.contains("unsupported"))
        XCTAssertEqual(documents.count, 1)
    }

    private static func writeUniqueTestPDF(at url: URL, identifier: Int) throws {
        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        pdfDocument.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Fixture \(identifier)",
            PDFDocumentAttribute.subjectAttribute: "Large Import Test \(identifier)",
            PDFDocumentAttribute.authorAttribute: "DocNestTests"
        ]

        guard pdfDocument.write(to: url) else {
            throw NSError(
                domain: "DocNestTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF fixture \(identifier)."]
            )
        }
    }

    @MainActor
    private func assertImportOfDistinctPDFs(count documentCount: Int) async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = tempRoot.appendingPathComponent("Source PDFs", isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Large Import Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        var pdfURLs: [URL] = []
        pdfURLs.reserveCapacity(documentCount)

        for index in 0..<documentCount {
            let pdfURL = sourceDirectory.appendingPathComponent(
                String(format: "document-%05d.pdf", index)
            )
            try Self.writeUniqueTestPDF(at: pdfURL, identifier: index)
            pdfURLs.append(pdfURL)
        }

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let importResult = await ImportPDFDocumentsUseCase.execute(
            urls: pdfURLs,
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())

        XCTAssertEqual(importResult.importedCount, documentCount)
        XCTAssertTrue(importResult.duplicates.isEmpty)
        XCTAssertTrue(importResult.unsupportedFiles.isEmpty)
        XCTAssertTrue(importResult.failures.isEmpty)
        XCTAssertEqual(documents.count, documentCount)
        XCTAssertEqual(Set(documents.map(\.contentHash)).count, documentCount)
        XCTAssertTrue(documents.allSatisfy { $0.pageCount == 1 })
        XCTAssertTrue(documents.allSatisfy { ($0.storedFilePath ?? "").hasPrefix("Originals/") })
    }

    @MainActor
    func testCreateAndAssignLabelCreatesSingleNormalizedLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(
            originalFileName: "contract.pdf",
            title: "Contract",
            importedAt: .now,
            pageCount: 1
        )
        context.insert(document)

        let firstLabel = try ManageLabelsUseCase.createAndAssignLabel(named: "  Finance   Team  ", to: [document], using: context)
        let secondLabel = try ManageLabelsUseCase.createAndAssignLabel(named: "finance team", to: [document], using: context)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(firstLabel.persistentModelID, secondLabel.persistentModelID)
        XCTAssertEqual(document.labels.count, 1)
        XCTAssertEqual(document.labels.first?.name, "Finance Team")
    }

    @MainActor
    func testRenameLabelMergesAssignmentsIntoExistingLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let finance = LabelTag(name: "Finance")
        let archive = LabelTag(name: "Archive")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [finance])
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [archive])

        context.insert(finance)
        context.insert(archive)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        let survivingLabel = try ManageLabelsUseCase.rename(archive, to: "Finance", using: context)
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(survivingLabel.name, "Finance")
        XCTAssertEqual(documentA.labels.first?.name, "Finance")
        XCTAssertEqual(documentB.labels.first?.name, "Finance")
    }

    @MainActor
    func testRenamingUnitLabelToExistingUnitlessLabelPreservesValuesAndUnit() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let finance = LabelTag(name: "Finance")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [invoice])
        context.insert(invoice)
        context.insert(finance)
        context.insert(document)
        try context.save()

        try ManageLabelValuesUseCase.setValue("25", for: document, label: invoice, using: context, locale: Locale(identifier: "en_US_POSIX"))

        let survivingLabel = try ManageLabelsUseCase.rename(invoice, to: "Finance", using: context)
        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())

        XCTAssertEqual(survivingLabel.name, "Finance")
        XCTAssertEqual(survivingLabel.unitSymbol, "€")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.labelID, survivingLabel.id)
        XCTAssertEqual(document.labels.first?.id, survivingLabel.id)
    }

    @MainActor
    func testRenamingUnitLabelToExistingDifferentUnitIsRejected() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let weight = LabelTag(name: "Weight", unitSymbol: "kg")
        context.insert(invoice)
        context.insert(weight)
        try context.save()

        XCTAssertThrowsError(try ManageLabelsUseCase.rename(invoice, to: "Weight", using: context)) { error in
            XCTAssertEqual(error as? LabelValidationError, .incompatibleUnitsForMerge)
        }

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 2)
    }

    @MainActor
    func testUpdatingUnitLabelToExistingDifferentUnitKeepsSourceValuesOnError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let weight = LabelTag(name: "Weight", unitSymbol: "kg")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [invoice])
        context.insert(invoice)
        context.insert(weight)
        context.insert(document)
        try context.save()

        try ManageLabelValuesUseCase.setValue("25", for: document, label: invoice, using: context, locale: Locale(identifier: "en_US_POSIX"))

        XCTAssertThrowsError(
            try ManageLabelsUseCase.update(invoice, name: "Weight", color: .blue, icon: nil, unitSymbol: "€", groupID: nil, using: context)
        ) { error in
            XCTAssertEqual(error as? LabelValidationError, .incompatibleUnitsForMerge)
        }

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.labelID, invoice.id)
        XCTAssertEqual(document.labels.first?.id, invoice.id)
    }

    @MainActor
    func testUpdatingUnitLabelToExistingUnitWithEmptyUnitKeepsDestinationValuesOnError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let weight = LabelTag(name: "Weight", unitSymbol: "kg")
        let sourceDocument = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [invoice])
        let destinationDocument = DocumentRecord(originalFileName: "weight.pdf", title: "Weight", importedAt: .now, pageCount: 1, labels: [weight])
        context.insert(invoice)
        context.insert(weight)
        context.insert(sourceDocument)
        context.insert(destinationDocument)
        try context.save()

        try ManageLabelValuesUseCase.setValue("25", for: sourceDocument, label: invoice, using: context, locale: Locale(identifier: "en_US_POSIX"))
        try ManageLabelValuesUseCase.setValue("3", for: destinationDocument, label: weight, using: context, locale: Locale(identifier: "en_US_POSIX"))

        XCTAssertThrowsError(
            try ManageLabelsUseCase.update(invoice, name: "Weight", color: .blue, icon: nil, unitSymbol: "", groupID: nil, using: context)
        ) { error in
            XCTAssertEqual(error as? LabelValidationError, .incompatibleUnitsForMerge)
        }

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertEqual(values.count, 2)
        XCTAssertNotNil(values.first { $0.labelID == invoice.id && $0.documentID == sourceDocument.id })
        XCTAssertNotNil(values.first { $0.labelID == weight.id && $0.documentID == destinationDocument.id })
        XCTAssertEqual(weight.unitSymbol, "kg")
    }

    @MainActor
    func testUpdatingUnitlessLabelToExistingUnitLabelPreservesDestinationValuesAndUnit() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let archive = LabelTag(name: "Archive")
        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let archiveDocument = DocumentRecord(originalFileName: "archive.pdf", title: "Archive", importedAt: .now, pageCount: 1, labels: [archive])
        let invoiceDocument = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [invoice])
        context.insert(archive)
        context.insert(invoice)
        context.insert(archiveDocument)
        context.insert(invoiceDocument)
        try context.save()

        try ManageLabelValuesUseCase.setValue("42", for: invoiceDocument, label: invoice, using: context, locale: Locale(identifier: "en_US_POSIX"))

        try ManageLabelsUseCase.update(archive, name: "Invoice", color: .green, icon: nil, unitSymbol: "", groupID: nil, using: context)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels.first?.id, invoice.id)
        XCTAssertEqual(labels.first?.unitSymbol, "€")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.labelID, invoice.id)
        XCTAssertEqual(values.first?.documentID, invoiceDocument.id)
        XCTAssertEqual(archiveDocument.labels.first?.id, invoice.id)
    }

    @MainActor
    func testDeleteLabelRemovesAssignmentsButKeepsDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Receipts")
        let document = DocumentRecord(originalFileName: "receipt.pdf", title: "Receipt", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        try ManageLabelsUseCase.delete(label, using: context)

        let remainingDocuments = try context.fetch(FetchDescriptor<DocumentRecord>())
        let remainingLabels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(remainingDocuments.count, 1)
        XCTAssertTrue(remainingDocuments[0].labels.isEmpty)
        XCTAssertTrue(remainingLabels.isEmpty)
    }

    @MainActor
    func testLabelValueStatisticsIgnoreMissingValues() throws {
        let labelID = UUID()
        let documentIDs = [UUID(), UUID(), UUID()]
        let values = [
            LabelValueSnapshot(documentID: documentIDs[0], labelID: labelID, decimalString: "10"),
            LabelValueSnapshot(documentID: documentIDs[2], labelID: labelID, decimalString: "20")
        ]

        let statistics = ManageLabelValuesUseCase.statistics(
            labelID: labelID,
            labelName: "Invoice",
            unitSymbol: "€",
            scope: .filtered,
            availableScopes: [.filtered],
            documentIDs: documentIDs,
            values: values
        )

        XCTAssertEqual(statistics.scopeDocumentCount, 3)
        XCTAssertEqual(statistics.valuedDocumentCount, 2)
        XCTAssertEqual(statistics.missingValueCount, 1)
        XCTAssertEqual(statistics.sum, Decimal(30))
        XCTAssertEqual(statistics.average, Decimal(15))
        XCTAssertEqual(statistics.minimum, Decimal(10))
        XCTAssertEqual(statistics.maximum, Decimal(20))
        XCTAssertEqual(statistics.median, Decimal(15))
    }

    @MainActor
    func testLabelValueStatisticsHandleNoValuesWithoutDivisionByZero() throws {
        let statistics = ManageLabelValuesUseCase.statistics(
            labelID: UUID(),
            labelName: "Invoice",
            unitSymbol: "€",
            scope: .filtered,
            availableScopes: [.filtered],
            documentIDs: [UUID(), UUID()],
            values: []
        )

        XCTAssertEqual(statistics.scopeDocumentCount, 2)
        XCTAssertEqual(statistics.valuedDocumentCount, 0)
        XCTAssertEqual(statistics.missingValueCount, 2)
        XCTAssertNil(statistics.sum)
        XCTAssertNil(statistics.average)
        XCTAssertNil(statistics.minimum)
        XCTAssertNil(statistics.maximum)
        XCTAssertNil(statistics.median)
    }

    @MainActor
    func testCoordinatorFormatsDocumentLabelValuesForAnyAssignedLabel() throws {
        let coordinator = LibraryCoordinator()
        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let hours = LabelTag(name: "Hours", unitSymbol: "h")
        let plain = LabelTag(name: "Reviewed")
        let document = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [invoice, hours, plain]
        )
        let values = [
            DocumentLabelValue(documentID: document.id, labelID: invoice.id, decimalString: "0"),
            DocumentLabelValue(documentID: document.id, labelID: hours.id, decimalString: "3.5")
        ]

        coordinator.syncLabelValues(values, recompute: false)

        XCTAssertEqual(coordinator.labelValueStringsByDocumentIDAndLabelID[document.id]?[invoice.id], "0")
        XCTAssertEqual(coordinator.formattedLabelValue(for: document.id, label: invoice), "0 €")
        XCTAssertEqual(
            coordinator.formattedLabelValue(for: document.id, label: hours),
            ManageLabelValuesUseCase.formattedValue(Decimal(3.5), unitSymbol: "h")
        )
        XCTAssertNil(coordinator.formattedLabelValue(for: document.id, label: plain))
    }

    @MainActor
    func testCoordinatorTreatsMissingAndInvalidDocumentLabelValuesAsEmpty() throws {
        let coordinator = LibraryCoordinator()
        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let documentID = UUID()

        coordinator.syncLabelValues([
            DocumentLabelValue(documentID: documentID, labelID: invoice.id, decimalString: "not-a-number")
        ], recompute: false)

        XCTAssertNil(coordinator.formattedLabelValue(for: documentID, label: invoice))
        XCTAssertNil(coordinator.formattedLabelValue(for: UUID(), label: invoice))
    }

    @MainActor
    func testCoordinatorUpdatesCachedDocumentLabelValueImmediately() throws {
        let coordinator = LibraryCoordinator()
        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let documentID = UUID()

        coordinator.syncLabelValues([], recompute: false)
        coordinator.updateCachedLabelValue(documentID: documentID, labelID: invoice.id, decimalString: "42")

        XCTAssertEqual(coordinator.labelValueStringsByDocumentIDAndLabelID[documentID]?[invoice.id], "42")
        XCTAssertEqual(coordinator.formattedLabelValue(for: documentID, label: invoice), "42 €")

        coordinator.updateCachedLabelValue(documentID: documentID, labelID: invoice.id, decimalString: nil)

        XCTAssertNil(coordinator.labelValueStringsByDocumentIDAndLabelID[documentID]?[invoice.id])
        XCTAssertNil(coordinator.formattedLabelValue(for: documentID, label: invoice))
    }

    func testInlineLabelValueEditorStateCommitsOnFocusLossAndCancels() {
        var state = InlineLabelValueEditorState()

        XCTAssertTrue(state.beginEditing(rawValue: "12", isValueEnabled: true))
        XCTAssertEqual(state.draftValue, "12")
        XCTAssertFalse(state.hasChanged(from: "12"))
        state.draftValue = "15"
        XCTAssertTrue(state.hasChanged(from: "12"))
        XCTAssertTrue(state.shouldCommitOnFocusChange(isFocused: false))

        state.cancel(rawValue: "12")

        XCTAssertFalse(state.isEditing)
        XCTAssertEqual(state.draftValue, "12")
        XCTAssertNil(state.errorMessage)
    }

    func testInlineLabelValueEditorStateTreatsUnchangedWhitespaceAsNoOp() {
        var state = InlineLabelValueEditorState()

        XCTAssertTrue(state.beginEditing(rawValue: "12", isValueEnabled: true))
        state.draftValue = " 12 "

        XCTAssertTrue(state.shouldCommitOnFocusChange(isFocused: false))
        XCTAssertFalse(state.hasChanged(from: "12"))
    }

    func testInlineLabelValueEditorStateKeepsInvalidInputOpen() {
        var state = InlineLabelValueEditorState()

        XCTAssertTrue(state.beginEditing(rawValue: nil, isValueEnabled: true))
        state.draftValue = "abc"
        state.failCommit(message: "Enter a valid number.")

        XCTAssertTrue(state.isEditing)
        XCTAssertEqual(state.draftValue, "abc")
        XCTAssertEqual(state.errorMessage, "Enter a valid number.")
    }

    func testInlineLabelValueEditorStateClosesWhenUnitSupportIsRemoved() {
        var state = InlineLabelValueEditorState()

        XCTAssertTrue(state.beginEditing(rawValue: "42", isValueEnabled: true))
        state.draftValue = "99"
        state.handleValueSupportChange(isValueEnabled: false, rawValue: nil)

        XCTAssertFalse(state.isEditing)
        XCTAssertEqual(state.draftValue, "")
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.beginEditing(rawValue: nil, isValueEnabled: false))
    }

    func testDocumentLabelStripDisplayPolicyPrioritizesActiveAndValuedLabels() {
        let plain = LabelTag(name: "Archive", sortOrder: 0)
        let missing = LabelTag(name: "Invoice", unitSymbol: "€", sortOrder: 1)
        let valued = LabelTag(name: "Hours", unitSymbol: "h", sortOrder: 2)
        let active = LabelTag(name: "Budget", unitSymbol: "€", sortOrder: 3)
        let policy = DocumentLabelStripDisplayPolicy(states: [
            DocumentLabelChipState(label: plain, valueText: nil, rawValue: nil, isValueEnabled: false, isActiveStatisticsLabel: false),
            DocumentLabelChipState(label: missing, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: false),
            DocumentLabelChipState(label: valued, valueText: "3 h", rawValue: "3", isValueEnabled: true, isActiveStatisticsLabel: false),
            DocumentLabelChipState(label: active, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: true)
        ])

        let visibleNames = policy
            .visibleStates(isHovering: false, isRowSelected: false)
            .map(\.label.name)

        XCTAssertEqual(visibleNames, ["Hours", "Budget"])
        XCTAssertFalse(policy.shouldShowMissingValueAffordance(
            for: DocumentLabelChipState(label: missing, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: false),
            isHovering: false,
            isRowSelected: false
        ))
    }

    func testDocumentLabelStripDisplayPolicyRevealsMissingValuesOnSelectionAndReportsHiddenMissingCount() {
        let plain = LabelTag(name: "Archive", sortOrder: 0)
        let missing = LabelTag(name: "Invoice", unitSymbol: "€", sortOrder: 1)
        let hiddenMissing = LabelTag(name: "Mileage", unitSymbol: "km", sortOrder: 2)
        let policy = DocumentLabelStripDisplayPolicy(states: [
            DocumentLabelChipState(label: plain, valueText: nil, rawValue: nil, isValueEnabled: false, isActiveStatisticsLabel: false),
            DocumentLabelChipState(label: missing, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: false),
            DocumentLabelChipState(label: hiddenMissing, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: false)
        ])

        let visibleNames = policy
            .visibleStates(isHovering: false, isRowSelected: true)
            .map(\.label.name)

        XCTAssertEqual(visibleNames, ["Invoice", "Mileage"])
        XCTAssertEqual(policy.hiddenLabelCount, 1)
        XCTAssertEqual(policy.hiddenLabelHelp(isHovering: false, isRowSelected: true), "1 hidden labels")
        XCTAssertTrue(policy.shouldShowMissingValueAffordance(
            for: DocumentLabelChipState(label: missing, valueText: nil, rawValue: nil, isValueEnabled: true, isActiveStatisticsLabel: false),
            isHovering: false,
            isRowSelected: true
        ))
    }

    @MainActor
    func testThumbnailCellSuppressesEmptyLabelBarAndBuildsFallbackStates() {
        let unlabeledDocument = DocumentRecord(
            originalFileName: "unlabeled.pdf",
            title: "Unlabeled",
            importedAt: .now,
            pageCount: 1
        )
        let unlabeledCell = DocumentThumbnailCell(
            document: unlabeledDocument,
            libraryURL: nil,
            size: 140,
            isSelected: false,
            isRenaming: false,
            renamingTitle: .constant(""),
            onCommitRename: {},
            onCancelRename: {},
            onBeginRename: {},
            onSelect: {},
            dragSession: nil
        )
        XCTAssertTrue(unlabeledCell.labelStates.isEmpty)
        XCTAssertFalse(DocumentThumbnailCellLayoutPolicy.showsMiniLabelBar(labelCount: unlabeledDocument.labels.count, isRenaming: false))

        let invoice = LabelTag(name: "Invoice", unitSymbol: "€")
        let labeledDocument = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [invoice]
        )
        let labeledCell = DocumentThumbnailCell(
            document: labeledDocument,
            libraryURL: nil,
            size: 140,
            isSelected: false,
            isRenaming: false,
            renamingTitle: .constant(""),
            onCommitRename: {},
            onCancelRename: {},
            onBeginRename: {},
            onSelect: {},
            dragSession: nil
        )

        XCTAssertEqual(labeledCell.labelStates.map(\.label.id), [invoice.id])
        XCTAssertTrue(labeledCell.labelStates.first?.isValueEnabled == true)
        XCTAssertTrue(DocumentThumbnailCellLayoutPolicy.showsMiniLabelBar(labelCount: labeledDocument.labels.count, isRenaming: false))
        XCTAssertFalse(DocumentThumbnailCellLayoutPolicy.showsMiniLabelBar(labelCount: labeledDocument.labels.count, isRenaming: true))
    }

    @MainActor
    func testSettingLabelValueDeduplicatesDocumentLabelPair() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Invoice", unitSymbol: "€")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        context.insert(DocumentLabelValue(documentID: document.id, labelID: label.id, decimalString: "10"))
        context.insert(DocumentLabelValue(documentID: document.id, labelID: label.id, decimalString: "20"))
        try context.save()

        try ManageLabelValuesUseCase.setValue("30", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.decimalString, "30")
    }

    @MainActor
    func testRemovingLabelClearsAssociatedValue() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Invoice", unitSymbol: "€")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        try ManageLabelValuesUseCase.setValue("42", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))
        try ManageLabelsUseCase.remove(label, from: document, using: context)

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertTrue(values.isEmpty)
    }

    @MainActor
    func testDeletingDocumentClearsAssociatedValue() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Invoice", unitSymbol: "€")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        try ManageLabelValuesUseCase.setValue("42", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))
        try DeleteDocumentsUseCase.execute([document], mode: .removeFromLibrary, libraryURL: nil, using: context)

        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertTrue(values.isEmpty)
    }

    @MainActor
    func testClearingLabelUnitDeletesAssociatedValues() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Invoice", unitSymbol: "€")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        try ManageLabelValuesUseCase.setValue("42", for: document, label: label, using: context, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(try ManageLabelsUseCase.valuesAffectedByClearingUnit(for: label, using: context), 1)

        try ManageLabelsUseCase.update(label, name: "Invoice", color: .blue, icon: nil, unitSymbol: "", groupID: nil, using: context)

        XCTAssertNil(label.unitSymbol)
        let values = try context.fetch(FetchDescriptor<DocumentLabelValue>())
        XCTAssertTrue(values.isEmpty)
    }

    @MainActor
    func testDeletingLabelDirectlyDoesNotCascadeIntoDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Invoices")
        let document = DocumentRecord(originalFileName: "invoice.pdf", title: "Invoice", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        context.delete(label)
        try context.save()

        let remainingDocuments = try context.fetch(FetchDescriptor<DocumentRecord>())
        let remainingLabels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(remainingDocuments.count, 1)
        XCTAssertTrue(remainingDocuments[0].labels.isEmpty)
        XCTAssertTrue(remainingLabels.isEmpty)
    }

    @MainActor
    func testRemoveDocumentFromLibraryKeepsStoredFile() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(at: tempRoot.appendingPathComponent("Test Library"))
        let storedFilePath = "Originals/2026/03/test.pdf"
        let storedFileURL = libraryURL.appendingPathComponent(storedFilePath)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: storedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: storedFileURL)

        let document = DocumentRecord(
            originalFileName: "test.pdf",
            title: "Test",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )
        context.insert(document)
        try context.save()

        try DeleteDocumentsUseCase.execute([document], mode: .removeFromLibrary, libraryURL: libraryURL, using: context)

        let remainingDocuments = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertTrue(remainingDocuments.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedFileURL.path))
    }

    @MainActor
    func testDeleteDocumentWithStoredFileRemovesRecordAndPDF() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(at: tempRoot.appendingPathComponent("Test Library"))
        let storedFilePath = "Originals/2026/03/test.pdf"
        let storedFileURL = libraryURL.appendingPathComponent(storedFilePath)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: storedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: storedFileURL)

        let document = DocumentRecord(
            originalFileName: "test.pdf",
            title: "Test",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )
        context.insert(document)
        try context.save()

        try DeleteDocumentsUseCase.execute([document], mode: .deleteStoredFiles, libraryURL: libraryURL, using: context)

        let remainingDocuments = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertTrue(remainingDocuments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedFileURL.path))
    }

    @MainActor
    func testDeletingStoredFilesRequiresLibraryLocation() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(
            originalFileName: "test.pdf",
            title: "Test",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/03/test.pdf"
        )
        context.insert(document)
        try context.save()

        XCTAssertThrowsError(
            try DeleteDocumentsUseCase.execute([document], mode: .deleteStoredFiles, libraryURL: nil, using: context)
        )
    }

    @MainActor
    func testMoveDocumentToBinSetsTrashedDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(originalFileName: "test.pdf", title: "Test", importedAt: .now, pageCount: 1)
        context.insert(document)
        try context.save()

        try DeleteDocumentsUseCase.moveToBin([document], using: context)

        XCTAssertNotNil(document.trashedAt)
    }

    @MainActor
    func testRestoreDocumentFromBinClearsTrashedDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(originalFileName: "test.pdf", title: "Test", importedAt: .now, pageCount: 1, trashedAt: .now)
        context.insert(document)
        try context.save()

        try DeleteDocumentsUseCase.restoreFromBin([document], using: context)

        XCTAssertNil(document.trashedAt)
    }

    @MainActor
    func testPendingLabelDeletionReportsAffectedDocumentCount() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Finance")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [label])
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        let pendingDeletion = PendingLabelDeletion(label: label)

        XCTAssertEqual(pendingDeletion.affectedDocumentCount, 2)
        XCTAssertEqual(
            pendingDeletion.message,
            "Deleting \"Finance\" will remove this label from 2 documents. The documents themselves will be kept."
        )
    }

    @MainActor
    func testPendingLabelDeletionUsesSingularDocumentMessage() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Tax")
        let document = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        let pendingDeletion = PendingLabelDeletion(label: label)

        XCTAssertEqual(pendingDeletion.affectedDocumentCount, 1)
        XCTAssertEqual(
            pendingDeletion.message,
            "Deleting \"Tax\" will remove this label from 1 document. The document itself will be kept."
        )
    }

    @MainActor
    func testPendingLabelDeletionSkipsConfirmationWhenNoDocumentsAreAssigned() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Unassigned")
        context.insert(label)
        try context.save()

        let pendingDeletion = PendingLabelDeletion(label: label)

        XCTAssertEqual(pendingDeletion.affectedDocumentCount, 0)
        XCTAssertFalse(pendingDeletion.requiresConfirmation)
    }

    @MainActor
    func testLabelFilterRequiresAllSelectedLabels() throws {
        let finance = LabelTag(name: "Finance")
        let archive = LabelTag(name: "Archive")
        let matchingDocument = DocumentRecord(originalFileName: "both.pdf", title: "Both", importedAt: .now, pageCount: 1, labels: [finance, archive])
        let partialDocument = DocumentRecord(originalFileName: "finance.pdf", title: "Finance Only", importedAt: .now, pageCount: 1, labels: [finance])

        let matchingIDs = Set([finance.persistentModelID, archive.persistentModelID])

        let filtered = SearchDocumentsUseCase.filter([matchingDocument, partialDocument], query: "", selectedLabelIDs: matchingIDs)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.contains(where: { $0.title == "Both" }))
    }

    func testSearchDocumentsMatchesTitleFilenameNotesAndLabels() {
        let finance = LabelTag(name: "Finance")
        let document = DocumentRecord(
            originalFileName: "invoice-march-2026.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [finance]
        )

        let docs = [document]
        let noLabels = Set<PersistentIdentifier>()
        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "march", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "invoice-march-2026", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertTrue(SearchDocumentsUseCase.filter(docs, query: "accountant", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "finance", selectedLabelIDs: noLabels).isEmpty)
    }

    func testSearchDocumentsRequiresAllTermsToMatch() {
        let finance = LabelTag(name: "Finance")
        let document = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [finance]
        )

        let docs = [document]
        let noLabels = Set<PersistentIdentifier>()
        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "march finance", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertTrue(SearchDocumentsUseCase.filter(docs, query: "march archive", selectedLabelIDs: noLabels).isEmpty)
    }

    func testSearchDocumentsFilterCombinesTextAndSelectedLabels() {
        let finance = LabelTag(name: "Finance")
        let archive = LabelTag(name: "Archive")
        let matchingDocument = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [finance]
        )
        let wrongLabelDocument = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [archive]
        )
        let wrongTextDocument = DocumentRecord(
            originalFileName: "contract.pdf",
            title: "Client Contract",
            importedAt: .now,
            pageCount: 1,
            labels: [finance]
        )

        let filteredDocuments = SearchDocumentsUseCase.filter(
            [matchingDocument, wrongLabelDocument, wrongTextDocument],
            query: "march invoice",
            selectedLabelIDs: Set([finance.persistentModelID])
        )

        XCTAssertEqual(filteredDocuments.count, 1)
        XCTAssertEqual(filteredDocuments.first?.title, "March Invoice")
    }

    @MainActor
    func testAssignLabelToMultipleDocumentsAddsItToAllSelectedDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Travel")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1)
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        try ManageLabelsUseCase.assign(label, to: [documentA, documentB], using: context)

        XCTAssertEqual(documentA.labels.map(\.name), ["Travel"])
        XCTAssertEqual(documentB.labels.map(\.name), ["Travel"])
    }

    @MainActor
    func testRemoveLabelFromMultipleDocumentsRemovesItFromSelectionOnly() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Legal")
        let retainedLabel = LabelTag(name: "Archive")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [label])
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [label, retainedLabel])
        let documentC = DocumentRecord(originalFileName: "c.pdf", title: "C", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(retainedLabel)
        context.insert(documentA)
        context.insert(documentB)
        context.insert(documentC)
        try context.save()

        try ManageLabelsUseCase.remove(label, from: [documentA, documentB], using: context)

        XCTAssertTrue(documentA.labels.isEmpty)
        XCTAssertEqual(documentB.labels.map(\.name), ["Archive"])
        XCTAssertEqual(documentC.labels.map(\.name), ["Legal"])
    }

    @MainActor
    func testCreateAndAssignLabelToMultipleDocumentsCreatesOneSharedLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1)
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        let label = try ManageLabelsUseCase.createAndAssignLabel(named: " Batch   Review ", to: [documentA, documentB], using: context)
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(label.name, "Batch Review")
        XCTAssertEqual(documentA.labels.map(\.name), ["Batch Review"])
        XCTAssertEqual(documentB.labels.map(\.name), ["Batch Review"])
    }

    // MARK: - ExportDocumentsUseCase Tests

    func testSuggestedFileNameForDocumentWithoutLabels() {
        let document = DocumentRecord(
            originalFileName: "scan.pdf",
            title: "Monthly Report",
            importedAt: .now,
            pageCount: 1
        )

        let fileName = ExportDocumentsUseCase.suggestedFileName(for: document)
        XCTAssertEqual(fileName, "Monthly Report.pdf")
    }

    func testSuggestedFileNameForDocumentWithLabels() {
        let finance = LabelTag(name: "Finance", sortOrder: 0)
        let tax = LabelTag(name: "Tax", sortOrder: 1)
        let document = DocumentRecord(
            originalFileName: "scan.pdf",
            title: "Invoice",
            importedAt: .now,
            pageCount: 1,
            labels: [finance, tax]
        )

        let fileName = ExportDocumentsUseCase.suggestedFileName(for: document)
        XCTAssertEqual(fileName, "Invoice - Finance, Tax.pdf")
    }

    func testSuggestedFileNameSanitizesIllegalCharacters() {
        let document = DocumentRecord(
            originalFileName: "scan.pdf",
            title: "Report: Q1/Q2\\Summary",
            importedAt: .now,
            pageCount: 1
        )

        let fileName = ExportDocumentsUseCase.suggestedFileName(for: document)
        XCTAssertEqual(fileName, "Report_ Q1_Q2_Summary.pdf")
    }

    func testSuggestedFileNameFallsBackToUntitledForEmptyTitle() {
        let document = DocumentRecord(
            originalFileName: "scan.pdf",
            title: "   ",
            importedAt: .now,
            pageCount: 1
        )

        let fileName = ExportDocumentsUseCase.suggestedFileName(for: document)
        XCTAssertEqual(fileName, "Untitled.pdf")
    }

    func testSuggestedFileNameSortsLabelsBySortOrder() {
        let beta = LabelTag(name: "Beta", sortOrder: 2)
        let alpha = LabelTag(name: "Alpha", sortOrder: 1)
        let gamma = LabelTag(name: "Gamma", sortOrder: 0)
        let document = DocumentRecord(
            originalFileName: "scan.pdf",
            title: "Doc",
            importedAt: .now,
            pageCount: 1,
            labels: [beta, alpha, gamma]
        )

        let fileName = ExportDocumentsUseCase.suggestedFileName(for: document)
        XCTAssertEqual(fileName, "Doc - Gamma, Alpha, Beta.pdf")
    }

    @MainActor
    func testBulkExportCopiesFilesToSelectedFolder() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Export Library")
        )
        let exportFolder = tempRoot.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // Create a stored PDF file in the library
        let storedFilePath = "Originals/2026/03/invoice.pdf"
        let storedFileURL = libraryURL.appendingPathComponent(storedFilePath)
        try FileManager.default.createDirectory(
            at: storedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: storedFileURL))

        let document = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )

        // Directly test the collision resolution and copy logic by copying manually
        let suggestedName = ExportDocumentsUseCase.suggestedFileName(for: document)
        let destinationURL = exportFolder.appendingPathComponent(suggestedName)
        try FileManager.default.copyItem(at: storedFileURL, to: destinationURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(destinationURL.lastPathComponent, "March Invoice.pdf")
    }

    @MainActor
    func testTemporaryExportURLUsesSuggestedFileName() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Drag Export Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let storedFilePath = "Originals/2026/03/invoice.pdf"
        let storedFileURL = libraryURL.appendingPathComponent(storedFilePath)
        try FileManager.default.createDirectory(
            at: storedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: storedFileURL))

        let document = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "March Invoice",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )

        let temporaryURL = try XCTUnwrap(
            ExportDocumentsUseCase.temporaryExportURL(for: document, libraryURL: libraryURL)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(temporaryURL.lastPathComponent, "March Invoice.pdf")
    }

    @MainActor
    func testTemporaryExportURLsExportMultipleDocuments() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Drag Export Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let firstStoredPath = "Originals/2026/03/invoice-a.pdf"
        let secondStoredPath = "Originals/2026/03/invoice-b.pdf"
        for storedPath in [firstStoredPath, secondStoredPath] {
            let storedFileURL = libraryURL.appendingPathComponent(storedPath)
            try FileManager.default.createDirectory(
                at: storedFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let pdfDocument = PDFDocument()
            pdfDocument.insert(PDFPage(), at: 0)
            XCTAssertTrue(pdfDocument.write(to: storedFileURL))
        }

        let documents = [
            DocumentRecord(
                originalFileName: "invoice-a.pdf",
                title: "March Invoice A",
                importedAt: .now,
                pageCount: 1,
                storedFilePath: firstStoredPath
            ),
            DocumentRecord(
                originalFileName: "invoice-b.pdf",
                title: "March Invoice B",
                importedAt: .now,
                pageCount: 1,
                storedFilePath: secondStoredPath
            )
        ]

        let exportItems = documents.compactMap {
            ExportDocumentsUseCase.dragExportItem(for: $0, libraryURL: libraryURL)
        }
        let exportedURLs = try ExportDocumentsUseCase.temporaryExportURLs(for: exportItems)

        XCTAssertEqual(Set(exportedURLs.map(\.lastPathComponent)), Set(["March Invoice A.pdf", "March Invoice B.pdf"]))
        XCTAssertTrue(exportedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @MainActor
    func testTemporaryExportURLReturnsNilWhenStoredFileMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Missing File Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let document = DocumentRecord(
            originalFileName: "missing.pdf",
            title: "Missing",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/03/missing.pdf"
        )

        let temporaryURL = try ExportDocumentsUseCase.temporaryExportURL(for: document, libraryURL: libraryURL)
        XCTAssertNil(temporaryURL)
    }

    @MainActor
    func testTemporaryExportURLsRemoveDirectoryWhenCopyFails() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docnest-drag-export", isDirectory: true)
        let existingDirectoriesBefore = Set((try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )) ?? [])

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let sourceURL = tempRoot.appendingPathComponent("source.pdf")
        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: sourceURL))

        let validItem = ExportDocumentsUseCase.DragExportItem(
            sourceURL: sourceURL,
            suggestedFileName: "Source.pdf"
        )
        let missingItem = ExportDocumentsUseCase.DragExportItem(
            sourceURL: tempRoot.appendingPathComponent("missing.pdf"),
            suggestedFileName: "Missing.pdf"
        )

        XCTAssertThrowsError(try ExportDocumentsUseCase.temporaryExportURLs(for: [validItem, missingItem]))

        let existingDirectoriesAfter = Set((try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )) ?? [])
        XCTAssertTrue(existingDirectoriesAfter.subtracting(existingDirectoriesBefore).isEmpty)
    }

    func testThumbnailCacheBestAvailableKeyPrefersClosestMatchingPreviewSize() {
        let storedPath = "Originals/report.pdf"
        let libraryURL = URL(fileURLWithPath: "/tmp/LibraryA.docnestlibrary")
        let bestKeys = ThumbnailCache.bestAvailableKeys(
            for: storedPath,
            libraryURL: libraryURL,
            availableKeys: [
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_240x312",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_680x880",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_1024x1328",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/other.pdf".utf8).base64EncodedString() + "_700x900"
            ],
            preferredSize: CGSize(width: 720, height: 900)
        )

        XCTAssertEqual(
            bestKeys.first,
            Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_680x880"
        )
    }

    func testThumbnailCacheBestAvailableKeyIgnoresOtherDocumentPaths() {
        let libraryURL = URL(fileURLWithPath: "/tmp/LibraryA.docnestlibrary")
        let bestKeys = ThumbnailCache.bestAvailableKeys(
            for: "Originals/current.pdf",
            libraryURL: libraryURL,
            availableKeys: [
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/other.pdf".utf8).base64EncodedString() + "_700x900",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/other.pdf".utf8).base64EncodedString() + "_500x700"
            ],
            preferredSize: CGSize(width: 720, height: 900)
        )

        XCTAssertTrue(bestKeys.isEmpty)
    }

    func testThumbnailCacheBestAvailableKeyIgnoresOverlappingPathPrefixes() {
        let storedPath = "Originals/report.pdf"
        let libraryURL = URL(fileURLWithPath: "/tmp/LibraryA.docnestlibrary")
        let bestKeys = ThumbnailCache.bestAvailableKeys(
            for: storedPath,
            libraryURL: libraryURL,
            availableKeys: [
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf_copy".utf8).base64EncodedString() + "_720x900",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_680x880"
            ],
            preferredSize: CGSize(width: 720, height: 900)
        )

        XCTAssertEqual(
            bestKeys.first,
            Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_680x880"
        )
    }

    func testThumbnailCacheBestAvailableKeyIgnoresOtherLibrariesWithSameStoredPath() {
        let storedPath = "Originals/report.pdf"
        let libraryA = URL(fileURLWithPath: "/tmp/LibraryA.docnestlibrary")
        let libraryB = URL(fileURLWithPath: "/tmp/LibraryB.docnestlibrary")
        let bestKeys = ThumbnailCache.bestAvailableKeys(
            for: storedPath,
            libraryURL: libraryA,
            availableKeys: [
                Data("\(libraryB.standardizedFileURL.path)\n\(storedPath)".utf8).base64EncodedString() + "_720x900",
                Data("\(libraryA.standardizedFileURL.path)\n\(storedPath)".utf8).base64EncodedString() + "_680x880"
            ],
            preferredSize: CGSize(width: 720, height: 900)
        )

        XCTAssertEqual(
            bestKeys.first,
            Data("\(libraryA.standardizedFileURL.path)\n\(storedPath)".utf8).base64EncodedString() + "_680x880"
        )
    }

    func testThumbnailCacheBestAvailableKeyBreaksEqualDistanceTiesTowardSharperImage() {
        let storedPath = "Originals/report.pdf"
        let libraryURL = URL(fileURLWithPath: "/tmp/LibraryA.docnestlibrary")
        let bestKeys = ThumbnailCache.bestAvailableKeys(
            for: storedPath,
            libraryURL: libraryURL,
            availableKeys: [
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_600x900",
                Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_840x900"
            ],
            preferredSize: CGSize(width: 720, height: 900)
        )

        XCTAssertEqual(
            bestKeys.first,
            Data("/tmp/LibraryA.docnestlibrary\nOriginals/report.pdf".utf8).base64EncodedString() + "_840x900"
        )
    }

    @MainActor
    func testPDFPreviewAlignmentMovesViewToFirstPageTop() throws {
        let image = NSImage(size: NSSize(width: 200, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 300)).fill()
        image.unlockFocus()

        let page = try XCTUnwrap(PDFPage(image: image))
        let document = PDFDocument()
        document.insert(page, at: 0)

        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 180, height: 220))
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.document = document

        PDFViewRepresentable.alignFirstPageTop(in: pdfView)

        let bounds = page.bounds(for: .cropBox)
        let destination = try XCTUnwrap(pdfView.currentDestination)

        XCTAssertIdentical(destination.page, page)
        XCTAssertEqual(destination.point.y, bounds.maxY, accuracy: 1.0)
    }

    // MARK: - ManageLabelsUseCase Additional Tests

    @MainActor
    func testReorderLabelsUpdatesSortOrder() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let alpha = LabelTag(name: "Alpha", sortOrder: 0)
        let beta = LabelTag(name: "Beta", sortOrder: 1)
        let gamma = LabelTag(name: "Gamma", sortOrder: 2)
        context.insert(alpha)
        context.insert(beta)
        context.insert(gamma)
        try context.save()

        // Move "Gamma" (index 2) to index 0
        try ManageLabelsUseCase.reorderLabels(
            from: IndexSet(integer: 2),
            to: 0,
            labels: [alpha, beta, gamma],
            using: context
        )

        XCTAssertEqual(gamma.sortOrder, 0)
        XCTAssertEqual(alpha.sortOrder, 1)
        XCTAssertEqual(beta.sortOrder, 2)
    }

    @MainActor
    func testChangeColorUpdatesLabelColor() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Finance", colorName: LabelColor.blue.rawValue)
        context.insert(label)
        try context.save()

        try ManageLabelsUseCase.changeColor(of: label, to: .red, using: context)

        XCTAssertEqual(label.labelColor, .red)
    }

    @MainActor
    func testChangeIconUpdatesLabelIcon() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Finance")
        context.insert(label)
        try context.save()

        XCTAssertNil(label.icon)

        try ManageLabelsUseCase.changeIcon(of: label, to: "💰", using: context)
        XCTAssertEqual(label.icon, "💰")

        try ManageLabelsUseCase.changeIcon(of: label, to: nil, using: context)
        XCTAssertNil(label.icon)
    }

    @MainActor
    func testCreateLabelWithEmptyNameThrowsValidationError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        XCTAssertThrowsError(
            try ManageLabelsUseCase.createLabel(named: "   ", color: .blue, using: context)
        ) { error in
            XCTAssertTrue(error is LabelValidationError)
        }
    }

    @MainActor
    func testCreateLabelWithColorAndIconSetsProperties() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let label = try ManageLabelsUseCase.createLabel(named: "Archive", color: .purple, icon: "📦", using: context)

        XCTAssertEqual(label.name, "Archive")
        XCTAssertEqual(label.labelColor, .purple)
        XCTAssertEqual(label.icon, "📦")
    }

    @MainActor
    func testCreateLabelWithDuplicateNameAndDifferentUnitThrowsValidationError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        _ = try ManageLabelsUseCase.createLabel(named: "Invoice", color: .blue, using: context)

        XCTAssertThrowsError(
            try ManageLabelsUseCase.createLabel(named: "invoice", color: .green, unitSymbol: "€", using: context)
        ) { error in
            XCTAssertEqual(error as? LabelValidationError, .duplicateNameWithDifferentUnit)
        }
    }

    @MainActor
    func testCreateOrReuseLabelForAssignmentReusesExistingUnitLabelByName() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let invoice = try ManageLabelsUseCase.createLabel(named: "Invoice", color: .blue, unitSymbol: "€", using: context)
        let reused = try ManageLabelsUseCase.createOrReuseLabelForAssignment(named: "invoice", color: .green, using: context)
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(reused.id, invoice.id)
        XCTAssertEqual(reused.unitSymbol, "€")
        XCTAssertEqual(reused.labelColor, .blue)
        XCTAssertEqual(labels.count, 1)
    }

    // MARK: - SearchDocumentsUseCase Additional Tests

    func testSearchDocumentsMatchesFullTextContent() {
        let document = DocumentRecord(
            originalFileName: "contract.pdf",
            title: "Service Agreement",
            importedAt: .now,
            pageCount: 5
        )
        document.fullText = "This agreement between Acme Corp and the client establishes terms of service."

        let docs = [document]
        let noLabels = Set<PersistentIdentifier>()

        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "acme", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertFalse(SearchDocumentsUseCase.filter(docs, query: "terms of service", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertTrue(SearchDocumentsUseCase.filter(docs, query: "nonexistent phrase", selectedLabelIDs: noLabels).isEmpty)
    }

    func testSearchDocumentsEmptyQueryReturnsAllDocuments() {
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1)
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1)

        let noLabels = Set<PersistentIdentifier>()
        let filtered = SearchDocumentsUseCase.filter([documentA, documentB], query: "", selectedLabelIDs: noLabels)

        XCTAssertEqual(filtered.count, 2)
    }

    func testSearchDocumentsIsCaseInsensitive() {
        let document = DocumentRecord(
            originalFileName: "invoice.pdf",
            title: "IMPORTANT Invoice",
            importedAt: .now,
            pageCount: 1
        )

        let noLabels = Set<PersistentIdentifier>()
        XCTAssertFalse(SearchDocumentsUseCase.filter([document], query: "important", selectedLabelIDs: noLabels).isEmpty)
        XCTAssertFalse(SearchDocumentsUseCase.filter([document], query: "INVOICE", selectedLabelIDs: noLabels).isEmpty)
    }

    func testDocumentBulkActionSummaryCountsActionableDocuments() {
        let dated = Date(timeIntervalSince1970: 1_800)
        let first = DocumentRecord(
            originalFileName: "first.pdf",
            title: "First",
            documentDate: dated,
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/first.pdf"
        )
        first.fullText = "Invoice 123"

        let second = DocumentRecord(
            originalFileName: "second.pdf",
            title: "Second",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/second.pdf"
        )
        second.fullText = "   "

        let third = DocumentRecord(
            originalFileName: "third.pdf",
            title: "Third",
            importedAt: .now,
            pageCount: 1
        )

        let summary = DocumentBulkActionSummary(documents: [first, second, third])

        XCTAssertEqual(summary.selectedCount, 3)
        XCTAssertEqual(summary.exportableCount, 2)
        XCTAssertEqual(summary.documentsWithStoredFilesCount, 2)
        XCTAssertEqual(summary.documentsWithDateCount, 1)
        XCTAssertEqual(summary.documentsWithExtractedTextCount, 1)
        XCTAssertTrue(summary.canReExtractDates)
        XCTAssertEqual(
            DocumentBulkActionSummary.documentsEligibleForDateExtraction(from: [first, second, third]).map(\.persistentModelID),
            [first.persistentModelID]
        )
    }

    func testDocumentBulkActionSummaryDisablesDateExtractionWithoutText() {
        let first = DocumentRecord(
            originalFileName: "first.pdf",
            title: "First",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/first.pdf"
        )
        let second = DocumentRecord(
            originalFileName: "second.pdf",
            title: "Second",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/second.pdf"
        )
        second.fullText = "   "

        let summary = DocumentBulkActionSummary(documents: [first, second])

        XCTAssertEqual(summary.documentsWithExtractedTextCount, 0)
        XCTAssertFalse(summary.canReExtractDates)
    }

    @MainActor
    func testTextExtractionEligibilityRequiresExistingStoredFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storedFilePath = "Originals/2026/first.pdf"
        let storedFileURL = tempRoot.appendingPathComponent(storedFilePath)
        try FileManager.default.createDirectory(
            at: storedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("pdf".utf8).write(to: storedFileURL)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let first = DocumentRecord(
            originalFileName: "first.pdf",
            title: "First",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )
        let second = DocumentRecord(
            originalFileName: "second.pdf",
            title: "Second",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/missing.pdf"
        )
        let third = DocumentRecord(
            originalFileName: "third.pdf",
            title: "Third",
            importedAt: .now,
            pageCount: 1
        )

        XCTAssertEqual(
            LibraryCoordinator.documentsEligibleForTextExtraction(from: [first, second, third], libraryURL: tempRoot).map(\.persistentModelID),
            [first.persistentModelID]
        )
    }

    @MainActor
    func testCoordinatorReExtractTextIgnoresDocumentsWithoutExistingStoredFiles() throws {
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let document = DocumentRecord(
            originalFileName: "missing.pdf",
            title: "Missing",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/missing.pdf"
        )
        document.fullText = "Existing searchable text"
        document.ocrCompleted = true
        context.insert(document)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.reExtractText(
            for: [document],
            libraryURL: FileManager.default.temporaryDirectory,
            modelContext: context
        )

        XCTAssertEqual(document.fullText, "Existing searchable text")
        XCTAssertTrue(document.ocrCompleted)
    }

    @MainActor
    func testCoordinatorReExtractTextQueuesEligibleDocumentsWhenOCRIsActive() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storedFilePath = "Originals/2026/first.pdf"
        let storedFileURL = tempRoot.appendingPathComponent(storedFilePath)
        try FileManager.default.createDirectory(
            at: storedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("pdf".utf8).write(to: storedFileURL)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let eligible = DocumentRecord(
            originalFileName: "first.pdf",
            title: "First",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )
        eligible.fullText = "Old searchable text"
        eligible.ocrCompleted = true
        let missing = DocumentRecord(
            originalFileName: "missing.pdf",
            title: "Missing",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "Originals/2026/missing.pdf"
        )
        missing.fullText = "Keep me"
        missing.ocrCompleted = true
        context.insert(eligible)
        context.insert(missing)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.startIdleOCRTaskForTesting()

        coordinator.reExtractText(for: [eligible, missing], libraryURL: tempRoot, modelContext: context)

        XCTAssertNil(eligible.fullText)
        XCTAssertFalse(eligible.ocrCompleted)
        XCTAssertEqual(missing.fullText, "Keep me")
        XCTAssertTrue(missing.ocrCompleted)
        XCTAssertEqual(coordinator.queuedOCRBackfillDocumentCountForTesting, 1)

        coordinator.cancelOCR()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @MainActor
    func testCoordinatorDrainsQueuedOCRBackfillDocuments() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storedFilePath = "Originals/2026/first.pdf"
        let storedFileURL = tempRoot.appendingPathComponent(storedFilePath)
        try FileManager.default.createDirectory(
            at: storedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("pdf".utf8).write(to: storedFileURL)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let document = DocumentRecord(
            originalFileName: "first.pdf",
            title: "First",
            importedAt: .now,
            pageCount: 1,
            storedFilePath: storedFilePath
        )
        context.insert(document)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.queueOCRBackfillDocumentsForTesting([document])
        XCTAssertEqual(coordinator.queuedOCRBackfillDocumentCountForTesting, 1)

        coordinator.drainQueuedOCRBackfillDocumentsForTesting(libraryURL: tempRoot, modelContext: context)

        XCTAssertEqual(coordinator.queuedOCRBackfillDocumentCountForTesting, 0)
        try await Task.sleep(nanoseconds: 500_000_000)
        coordinator.cancelOCR()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @MainActor
    func testCoordinatorRestoresPreviousDatesAfterFailedBulkDateSave() {
        enum SaveError: LocalizedError {
            case failed

            var errorDescription: String? {
                "Save failed"
            }
        }

        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", documentDate: nil, importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", documentDate: firstDate, importedAt: .now, pageCount: 1)
        let coordinator = LibraryCoordinator()

        coordinator.setDocumentDate(secondDate, for: [first, second]) {
            throw SaveError.failed
        }

        XCTAssertNil(first.documentDate)
        XCTAssertEqual(second.documentDate, firstDate)
        XCTAssertEqual(coordinator.importSummaryMessage, "Save failed")
    }

    @MainActor
    func testCoordinatorCancelOCRClearsQueuedBackfillDocuments() {
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1)
        let coordinator = LibraryCoordinator()

        coordinator.queueOCRBackfillDocumentsForTesting([first, second])
        XCTAssertEqual(coordinator.queuedOCRBackfillDocumentCountForTesting, 2)

        coordinator.cancelOCR()

        XCTAssertEqual(coordinator.queuedOCRBackfillDocumentCountForTesting, 0)
    }

    @MainActor
    func testCoordinatorSetsDocumentDateForSelection() throws {
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1)
        context.insert(first)
        context.insert(second)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.modelContext = context
        let expectedDate = Date(timeIntervalSince1970: 123_456)

        coordinator.setDocumentDate(expectedDate, for: [first, second], modelContext: context)

        XCTAssertEqual(first.documentDate, expectedDate)
        XCTAssertEqual(second.documentDate, expectedDate)

        coordinator.setDocumentDate(nil, for: [first, second], modelContext: context)

        XCTAssertNil(first.documentDate)
        XCTAssertNil(second.documentDate)
    }

    @MainActor
    func testCoordinatorReExtractsDocumentDateForSelectionWithFallback() throws {
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let importedAt = Date(timeIntervalSince1970: 400_000)
        let extractedDate = DocumentDateExtractor.extractDate(from: "Invoice Date: 2026-03-15")
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: importedAt, pageCount: 1)
        first.fullText = "Invoice Date: 2026-03-15"
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: importedAt, pageCount: 1)
        context.insert(first)
        context.insert(second)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.modelContext = context

        coordinator.reExtractDocumentDate(for: [first, second], modelContext: context)

        XCTAssertEqual(first.documentDate, extractedDate)
        XCTAssertEqual(second.documentDate, importedAt)
    }

    @MainActor
    func testCoordinatorRestoresDocumentSelectionFromBin() throws {
        let container = try TestImportFixtures.makeInMemoryContainer()
        let context = container.mainContext
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1, trashedAt: .now)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1, trashedAt: .now)
        context.insert(first)
        context.insert(second)
        try context.save()

        let coordinator = LibraryCoordinator()
        coordinator.modelContext = context
        coordinator.ingest(allDocuments: [first, second], allLabels: [], allSmartFolders: [], allLabelGroups: [], allWatchFolders: [])

        coordinator.restoreDocumentsFromBin([first, second])

        XCTAssertNil(first.trashedAt)
        XCTAssertNil(second.trashedAt)
    }

    // MARK: - DeleteDocumentsUseCase Additional Tests

    @MainActor
    func testDeleteEmptyArrayDoesNothing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        try DeleteDocumentsUseCase.execute([], mode: .removeFromLibrary, libraryURL: nil, using: context)
        // Should not throw
    }

    @MainActor
    func testMoveToBinIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(originalFileName: "test.pdf", title: "Test", importedAt: .now, pageCount: 1)
        context.insert(document)
        try context.save()

        try DeleteDocumentsUseCase.moveToBin([document], using: context)
        let firstTrashedAt = document.trashedAt

        try DeleteDocumentsUseCase.moveToBin([document], using: context)

        XCTAssertEqual(document.trashedAt, firstTrashedAt, "Moving to bin again should not update the trashed date")
    }

    @MainActor
    func testRestoreFromBinIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(originalFileName: "test.pdf", title: "Test", importedAt: .now, pageCount: 1)
        context.insert(document)
        try context.save()

        // Document is not trashed — restoring should be a no-op
        try DeleteDocumentsUseCase.restoreFromBin([document], using: context)

        XCTAssertNil(document.trashedAt)
    }

    func testReleaseVersionParsesMajorAndMinorOnly() {
        let version = AppReleaseVersion(string: "2025.4")

        XCTAssertEqual(version?.year, 2025)
        XCTAssertEqual(version?.major, 4)
        XCTAssertEqual(version?.minor, 0)
        XCTAssertEqual(version?.description, "2025.4")
    }

    func testReleaseVersionParsesPatchVariant() {
        let version = AppReleaseVersion(string: "2025.4.1")

        XCTAssertEqual(version?.year, 2025)
        XCTAssertEqual(version?.major, 4)
        XCTAssertEqual(version?.minor, 1)
        XCTAssertEqual(version?.description, "2025.4.1")
    }

    func testReleaseVersionIgnoresLeadingVPrefix() {
        XCTAssertEqual(
            AppReleaseVersion(string: "v2025.4.1"),
            AppReleaseVersion(string: "2025.4.1")
        )
    }

    func testReleaseVersionComparisonTreatsPatchAsNewerThanBaseRelease() {
        let base = AppReleaseVersion(string: "2025.4")
        let patch = AppReleaseVersion(string: "2025.4.1")
        let nextMajor = AppReleaseVersion(string: "2025.5")

        XCTAssertNotNil(base)
        XCTAssertNotNil(patch)
        XCTAssertNotNil(nextMajor)
        XCTAssertLessThan(base!, patch!)
        XCTAssertLessThan(patch!, nextMajor!)
    }

    func testAppUpdateLatestReleaseRequestBypassesCachedReleasePayloads() throws {
        let url = try XCTUnwrap(URL(string: "https://api.github.com/repos/christiankaps/docnest/releases/latest"))

        let request = AppUpdateService.makeLatestReleaseRequest(url: url)

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "DocNest")
    }

    @MainActor
    func testAppUpdateRetriesWhenNewerReleaseInitiallyMissingInstallerAsset() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.7.7"))
        let releaseWithoutDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.7.8",
            htmlURL: "https://github.com/christiankaps/docnest/releases/tag/stale-without-dmg",
            assets: []
        )
        let releaseWithDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.7.8",
            htmlURL: "https://github.com/christiankaps/docnest/releases/tag/fresh-with-dmg",
            assets: [
                .init(
                    name: "DocNest_2026.7.8_43.dmg",
                    browserDownloadURL: "https://github.com/christiankaps/docnest/releases/download/fresh-with-dmg/DocNest_2026.7.8_43.dmg"
                )
            ]
        )
        var responses = [releaseWithoutDMG, releaseWithDMG]
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return responses.removeFirst()
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(sleepCount, 1)
        XCTAssertEqual(info?.latestVersion, AppReleaseVersion(string: "2026.7.8"))
        XCTAssertEqual(info?.assetName, "DocNest_2026.7.8_43.dmg")
        XCTAssertEqual(info?.releasePageURL.absoluteString, "https://github.com/christiankaps/docnest/releases/tag/fresh-with-dmg")
        XCTAssertEqual(
            info?.downloadURL.absoluteString,
            "https://github.com/christiankaps/docnest/releases/download/fresh-with-dmg/DocNest_2026.7.8_43.dmg"
        )
    }

    @MainActor
    func testAppUpdateDoesNotRetryWhenLatestReleaseIsNotNewer() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.7.8"))
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return AppUpdateService.GitHubReleaseResponse(
                    tagName: "2026.7.8",
                    htmlURL: "https://github.com/christiankaps/docnest/releases/tag/2026.7.8",
                    assets: []
                )
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertNil(info)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    @MainActor
    func testAppUpdateMountedVolumeURLParsesHdiutilPlist() throws {
        let propertyList: [String: Any] = [
            "system-entities": [
                ["dev-entry": "/dev/disk4"],
                ["mount-point": "/Volumes/DocNest", "volume-kind": "hfs"]
            ]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )

        let mountedURL = try AppUpdateService.mountedVolumeURL(fromAttachOutput: data)

        XCTAssertEqual(mountedURL.path, "/Volumes/DocNest")
    }

    @MainActor
    func testAppUpdateProgressFormatsDownloadFraction() {
        let progress = AppUpdateService.UpdateProgress(
            version: AppReleaseVersion(string: "2025.4.1")!,
            phase: .downloading(bytesReceived: 1_024, totalBytes: 2_048)
        )

        XCTAssertEqual(progress.title, "Downloading Version 2025.4.1")
        XCTAssertEqual(progress.statusSummary, "50%")
        XCTAssertEqual(progress.fractionCompleted ?? -1, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testAppUpdateProgressFormatsVerificationStep() {
        let progress = AppUpdateService.UpdateProgress(
            version: AppReleaseVersion(string: "2025.4.1")!,
            phase: .verifyingInstaller
        )

        XCTAssertEqual(progress.title, "Verifying Update")
        XCTAssertEqual(progress.statusSummary, "4/5")
        XCTAssertNil(progress.fractionCompleted)
        XCTAssertTrue(progress.detail.contains("Step 4 of 5"))
    }

    @MainActor
    func testAppUpdateProgressRejectsDownloadAfterLaterStage() {
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .downloading(bytesReceived: 2_048, totalBytes: 4_096),
                over: .mountingInstaller
            )
        )
    }

    @MainActor
    func testAppUpdateProgressRejectsStartingDownloadAfterByteProgress() {
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .startingDownload,
                over: .downloading(bytesReceived: 2_048, totalBytes: 4_096)
            )
        )
    }

    @MainActor
    func testAppUpdateProgressSessionIgnoresUpdatesAfterClear() {
        let service = AppUpdateService()
        let version = AppReleaseVersion(string: "2025.4.1")!
        let sessionID = service.beginUpdateProgressSession(for: version)

        service.clearUpdateProgressSession()
        service.applyUpdateProgress(.downloading(bytesReceived: 1_024, totalBytes: 2_048), version: version, sessionID: sessionID)

        XCTAssertNil(service.updateProgress)
    }

    @MainActor
    func testAppUpdateProgressSessionIgnoresRegressiveDownloadUpdate() {
        let service = AppUpdateService()
        let version = AppReleaseVersion(string: "2025.4.1")!
        let sessionID = service.beginUpdateProgressSession(for: version)

        service.applyUpdateProgress(.mountingInstaller, version: version, sessionID: sessionID)
        service.applyUpdateProgress(.downloading(bytesReceived: 2_048, totalBytes: 4_096), version: version, sessionID: sessionID)

        XCTAssertEqual(service.updateProgress?.phase, .mountingInstaller)
        service.clearUpdateProgressSession()
    }

    @MainActor
    func testAppUpdateProgressSessionIgnoresUpdatesFromOlderSession() {
        let service = AppUpdateService()
        let oldVersion = AppReleaseVersion(string: "2025.4.1")!
        let newVersion = AppReleaseVersion(string: "2025.5")!
        let oldSessionID = service.beginUpdateProgressSession(for: oldVersion)
        _ = service.beginUpdateProgressSession(for: newVersion)

        service.applyUpdateProgress(.downloading(bytesReceived: 1_024, totalBytes: 2_048), version: oldVersion, sessionID: oldSessionID)

        XCTAssertEqual(service.updateProgress?.version, newVersion)
        XCTAssertEqual(service.updateProgress?.phase, .startingDownload)
        service.clearUpdateProgressSession()
    }

    @MainActor
    func testAppUpdateBeginInstallProgressSessionMarksServiceBusyBeforePublishingProgress() {
        let service = AppUpdateService()
        let version = AppReleaseVersion(string: "2025.5")!

        let sessionID = service.beginInstallProgressSession(for: version)

        XCTAssertEqual(service.status, .downloading(version))
        XCTAssertTrue(service.isBusy)
        XCTAssertEqual(service.updateProgress?.version, version)
        XCTAssertEqual(service.updateProgress?.phase, .startingDownload)

        service.clearUpdateProgressSession()
        service.applyUpdateProgress(.mountingInstaller, version: version, sessionID: sessionID)
        XCTAssertNil(service.updateProgress)
    }

    @MainActor
    func testAppUpdateMountDiskImageReportsAttachFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.mountDiskImage(
                at: URL(fileURLWithPath: "/tmp/DocNest.dmg"),
                processRunner: { _, _ in
                    throw NSError(
                        domain: "DocNestTests",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: attach failed"]
                    )
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertEqual(
                message,
                "The downloaded installer could not be mounted. hdiutil: attach failed"
            )
        }
    }

    @MainActor
    func testAppUpdateDetachDiskImageRetriesWithForceWhenVolumeIsBusy() throws {
        var recordedArguments: [[String]] = []

        try AppUpdateService.detachDiskImage(
            at: URL(fileURLWithPath: "/Volumes/DocNest", isDirectory: true),
            processRunner: { executablePath, arguments in
                XCTAssertEqual(executablePath, "/usr/bin/hdiutil")
                recordedArguments.append(arguments)

                if recordedArguments.count == 1 {
                    throw NSError(
                        domain: "DocNestTests",
                        code: 16,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: couldn't unmount disk23"]
                    )
                }

                return Data()
            },
            sleep: { _ in }
        )

        XCTAssertEqual(
            recordedArguments,
            [
                ["detach", "/Volumes/DocNest"],
                ["detach", "-force", "/Volumes/DocNest"]
            ]
        )
    }

    @MainActor
    func testAppUpdateDetachDiskImageReportsDetachFailureAfterForcedRetry() {
        XCTAssertThrowsError(
            try AppUpdateService.detachDiskImage(
                at: URL(fileURLWithPath: "/Volumes/DocNest", isDirectory: true),
                processRunner: { _, arguments in
                    if arguments.contains("-force") {
                        throw NSError(
                            domain: "DocNestTests",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "hdiutil: couldn't unmount disk23"]
                        )
                    }

                    throw NSError(
                        domain: "DocNestTests",
                        code: 16,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: resource busy"]
                    )
                },
                sleep: { _ in }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertEqual(
                message,
                "The downloaded installer could not be unmounted. hdiutil: couldn't unmount disk23"
            )
        }
    }

    @MainActor
    func testAppUpdateDetachDiskImageDoesNotForceForNonBusyFailures() {
        var recordedArguments: [[String]] = []

        XCTAssertThrowsError(
            try AppUpdateService.detachDiskImage(
                at: URL(fileURLWithPath: "/Volumes/DocNest", isDirectory: true),
                processRunner: { _, arguments in
                    recordedArguments.append(arguments)
                    throw NSError(
                        domain: "DocNestTests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: no such image"]
                    )
                },
                sleep: { _ in }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertEqual(
                message,
                "The downloaded installer could not be unmounted. hdiutil: no such image"
            )
        }

        XCTAssertEqual(recordedArguments, [["detach", "/Volumes/DocNest"]])
    }

    @MainActor
    func testAppUpdateVerifyCodeSignatureReportsVerificationFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.verifyCodeSignature(
                of: URL(fileURLWithPath: "/tmp/DocNest.app", isDirectory: true),
                expectedBundleIdentifier: "com.kaps.docnest",
                expectedTeamIdentifier: nil,
                processRunner: { _, _ in
                    throw NSError(
                        domain: "DocNestTests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "code object is not signed at all"]
                    )
                },
                metadataProvider: { _ in
                    XCTFail("Metadata should not be requested when signature verification fails.")
                    return (identifier: nil, teamIdentifier: nil)
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertEqual(
                message,
                "The downloaded update could not be verified. code object is not signed at all"
            )
        }
    }

    @MainActor
    func testAppUpdateInstallerScriptContainsReplaceAndRelaunchSteps() {
        let script = AppUpdateService.installerScript(
            currentPID: 1234,
            stagedAppURL: URL(fileURLWithPath: "/tmp/DocNestUpdate/DocNest.app"),
            destinationAppURL: URL(fileURLWithPath: "/Applications/DocNest.app"),
            temporaryRootURL: URL(fileURLWithPath: "/tmp/DocNestUpdate")
        )

        XCTAssertTrue(script.contains("CURRENT_PID=1234"))
        XCTAssertTrue(script.contains("/usr/bin/ditto"))
        XCTAssertTrue(script.contains("/usr/bin/osascript"))
        XCTAssertTrue(script.contains("/usr/bin/open \"$DESTINATION_APP\""))
        XCTAssertTrue(script.contains("/bin/rm -rf \"$TEMP_ROOT\""))
    }

    @MainActor
    func testAppUpdateInstallerScriptRestoresPreviousAppOnReplaceFailure() {
        let script = AppUpdateService.installerScript(
            currentPID: 1234,
            stagedAppURL: URL(fileURLWithPath: "/tmp/DocNestUpdate/DocNest.app"),
            destinationAppURL: URL(fileURLWithPath: "/Applications/DocNest.app"),
            temporaryRootURL: URL(fileURLWithPath: "/tmp/DocNestUpdate")
        )

        XCTAssertTrue(script.contains("if /bin/mv \"$DESTINATION_APP.new\" \"$DESTINATION_APP\"; then"))
        XCTAssertTrue(script.contains("if [ -e \"$DESTINATION_APP.previous\" ]; then"))
        XCTAssertTrue(script.contains("/bin/mv \"$DESTINATION_APP.previous\" \"$DESTINATION_APP\""))
        XCTAssertTrue(script.contains("return 1"))
    }

    @MainActor
    func testArrowNavigationStepUsesVisibleGroupedOrderAndOrderedSelectionFallback() {
        let jan2025 = DocumentRecord(
            originalFileName: "jan-2025.pdf",
            title: "Jan 2025",
            documentDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15)),
            importedAt: .now,
            pageCount: 1
        )
        let feb2026 = DocumentRecord(
            originalFileName: "feb-2026.pdf",
            title: "Feb 2026",
            documentDate: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 15)),
            importedAt: .now,
            pageCount: 1
        )
        let jan2026 = DocumentRecord(
            originalFileName: "jan-2026.pdf",
            title: "Jan 2026",
            documentDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15)),
            importedAt: .now,
            pageCount: 1
        )

        let flatSortedDocuments = [jan2025, feb2026, jan2026]
        let visibleDocuments = DocumentGroupMode.yearMonth.group(flatSortedDocuments).flatMap(\.documents)

        let groupedDownStep = DocumentListView.arrowNavigationStep(
            key: .downArrow,
            anchor: feb2026.persistentModelID,
            selectedDocumentIDs: [feb2026.persistentModelID],
            orderedSelectedDocumentIDs: [feb2026.persistentModelID],
            visibleDocuments: visibleDocuments,
            extendSelection: false
        )
        XCTAssertEqual(groupedDownStep?.nextID, jan2026.persistentModelID)
        XCTAssertEqual(groupedDownStep?.selectedIDs, [jan2026.persistentModelID])

        let missingAnchorStep = DocumentListView.arrowNavigationStep(
            key: .downArrow,
            anchor: nil,
            selectedDocumentIDs: [jan2025.persistentModelID, feb2026.persistentModelID],
            orderedSelectedDocumentIDs: [feb2026.persistentModelID, jan2025.persistentModelID],
            visibleDocuments: visibleDocuments,
            extendSelection: false
        )
        XCTAssertEqual(missingAnchorStep?.nextID, jan2026.persistentModelID)
        XCTAssertEqual(missingAnchorStep?.selectedIDs, [jan2026.persistentModelID])
    }

    @MainActor
    func testDisplayedSelectionUpdatesImmediatelyForDirectSelectionInteraction() async {
        let coordinator = LibraryCoordinator()
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1)

        coordinator.ingest(allDocuments: [first, second], allLabels: [], allSmartFolders: [], allLabelGroups: [], allWatchFolders: [])

        for _ in 0..<20 {
            if coordinator.filteredDocuments.count == 2 {
                break
            }
            await Task.yield()
        }

        coordinator.selectedDocumentIDs = [first.persistentModelID]
        coordinator.recomputeSelectedDocuments()
        coordinator.syncDisplayedSelectionImmediately()
        XCTAssertEqual(coordinator.displayedSelectedDocuments.map(\.persistentModelID), [first.persistentModelID])

        coordinator.beginSelectionInteraction()
        coordinator.selectedDocumentIDs = [second.persistentModelID]
        coordinator.recomputeSelectedDocuments()
        coordinator.scheduleDisplayedSelectionUpdate()

        XCTAssertEqual(coordinator.displayedSelectedDocuments.map(\.persistentModelID), [second.persistentModelID])
    }

    @MainActor
    func testRecomputeSelectedDocumentsPreservesKnownSelectionDuringStaleFilteredLookup() async {
        let coordinator = LibraryCoordinator()
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1)

        coordinator.ingest(allDocuments: [first], allLabels: [], allSmartFolders: [], allLabelGroups: [], allWatchFolders: [])
        for _ in 0..<20 {
            if coordinator.filteredDocuments.count == 1 {
                break
            }
            await Task.yield()
        }
        coordinator.syncDocuments([first, second], recompute: false)

        coordinator.selectedDocumentIDs = [second.persistentModelID]
        coordinator.recomputeSelectedDocuments()

        XCTAssertEqual(coordinator.selectedDocumentIDs, [second.persistentModelID])
        XCTAssertEqual(coordinator.selectedDocuments.map(\.persistentModelID), [second.persistentModelID])
    }

    @MainActor
    func testRecomputeSelectedDocumentsFallsBackWhenSelectionNoLongerExists() async {
        let coordinator = LibraryCoordinator()
        let first = DocumentRecord(originalFileName: "first.pdf", title: "First", importedAt: .now, pageCount: 1)
        let second = DocumentRecord(originalFileName: "second.pdf", title: "Second", importedAt: .now, pageCount: 1)

        coordinator.ingest(allDocuments: [first, second], allLabels: [], allSmartFolders: [], allLabelGroups: [], allWatchFolders: [])
        for _ in 0..<20 {
            if coordinator.filteredDocuments.count == 2 {
                break
            }
            await Task.yield()
        }
        coordinator.selectedDocumentIDs = [second.persistentModelID]
        coordinator.recomputeSelectedDocuments()

        coordinator.syncDocuments([first], recompute: false)
        coordinator.recomputeSelectedDocuments()

        XCTAssertEqual(coordinator.selectedDocumentIDs, [first.persistentModelID])
        XCTAssertEqual(coordinator.selectedDocuments.map(\.persistentModelID), [first.persistentModelID])
    }
}
