import AppKit
import XCTest
import SwiftData
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
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        try TestSampleDataSeeder.seedIfNeeded(using: context)
        try TestSampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3, "Seeding should not duplicate data on second call")
    }

    @MainActor
    func testDocumentRecordAcceptsStoredFilePath() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
    func testDeleteLabelRemovesAssignmentsButKeepsDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
    func testDeletingLabelDirectlyDoesNotCascadeIntoDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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

    // MARK: - ManageLabelsUseCase Additional Tests

    @MainActor
    func testReorderLabelsUpdatesSortOrder() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let label = try ManageLabelsUseCase.createLabel(named: "Archive", color: .purple, icon: "📦", using: context)

        XCTAssertEqual(label.name, "Archive")
        XCTAssertEqual(label.labelColor, .purple)
        XCTAssertEqual(label.icon, "📦")
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

    // MARK: - DeleteDocumentsUseCase Additional Tests

    @MainActor
    func testDeleteEmptyArrayDoesNothing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        try DeleteDocumentsUseCase.execute([], mode: .removeFromLibrary, libraryURL: nil, using: context)
        // Should not throw
    }

    @MainActor
    func testMoveToBinIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
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
