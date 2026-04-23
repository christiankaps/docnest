import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

struct ExportDocumentsResult {
    struct Failure {
        let title: String
        let message: String
    }

    let exportedCount: Int
    let skippedCount: Int
    let failures: [Failure]

    var hasUserMessage: Bool {
        skippedCount > 0 || !failures.isEmpty
    }

    var summaryMessage: String {
        var parts: [String] = []

        if exportedCount > 0 {
            parts.append(exportedCount == 1 ? "Exported 1 document" : "Exported \(exportedCount) documents")
        }

        if skippedCount > 0 {
            parts.append(skippedCount == 1 ? "1 skipped" : "\(skippedCount) skipped")
        }

        if !failures.isEmpty {
            parts.append(failures.count == 1 ? "1 failed" : "\(failures.count) failed")
        }

        if parts.isEmpty {
            return "Export complete."
        }

        return parts.joined(separator: ". ") + "."
    }
}

enum ExportDocumentsUseCase {
    struct DragExportItem {
        let sourceURL: URL
        let suggestedFileName: String
    }

    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "export")

    // MARK: - Filename generation

    static func suggestedFileName(for document: DocumentRecord) -> String {
        let sanitizedTitle = sanitizeForFilesystem(document.title)
        let labelSuffix = labelSuffix(for: document)

        if labelSuffix.isEmpty {
            return "\(sanitizedTitle).pdf"
        }

        return "\(sanitizedTitle) - \(labelSuffix).pdf"
    }

    // MARK: - Export

    /// Exports one or more documents. For a single document, presents an NSSavePanel.
    /// For multiple documents, presents an NSOpenPanel in folder-selection mode.
    /// Returns a result describing what happened, or `nil` if the user cancelled the panel.
    @MainActor
    static func exportDocuments(
        _ documents: [DocumentRecord],
        libraryURL: URL
    ) -> ExportDocumentsResult? {
        guard !documents.isEmpty else { return nil }

        if documents.count == 1, let document = documents.first {
            return exportSingleDocument(document, libraryURL: libraryURL)
        }

        return exportMultipleDocuments(documents, libraryURL: libraryURL)
    }

    // MARK: - Private

    @MainActor
    private static func exportSingleDocument(
        _ document: DocumentRecord,
        libraryURL: URL
    ) -> ExportDocumentsResult? {
        guard sourceURL(for: document, libraryURL: libraryURL) != nil else {
            return nil
        }

        let suggestedName = suggestedFileName(for: document)
        let nameWithoutExtension = (suggestedName as NSString).deletingPathExtension

        let panel = NSSavePanel()
        panel.nameFieldStringValue = nameWithoutExtension
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return nil
        }

        do {
            try copyDocument(document, libraryURL: libraryURL, to: destinationURL)
            return ExportDocumentsResult(exportedCount: 1, skippedCount: 0, failures: [])
        } catch {
            logger.error("Failed to export '\(document.title)': \(error.localizedDescription)")
            return ExportDocumentsResult(
                exportedCount: 0,
                skippedCount: 0,
                failures: [.init(title: document.title, message: error.localizedDescription)]
            )
        }
    }

    @MainActor
    private static func exportMultipleDocuments(
        _ documents: [DocumentRecord],
        libraryURL: URL
    ) -> ExportDocumentsResult? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export \(documents.count) documents."

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return nil
        }

        // Collect copy operations on the main thread (needs SwiftData access),
        // then perform file I/O synchronously but off the main actor is not possible
        // since we need collision resolution to be sequential. The panel already
        // blocks the run loop, so the copy phase is fast relative to user wait.
        var exportedCount = 0
        var skippedCount = 0
        var failures: [ExportDocumentsResult.Failure] = []
        var usedFileNames: [String: Int] = [:]

        for document in documents {
            guard sourceURL(for: document, libraryURL: libraryURL) != nil else {
                skippedCount += 1
                continue
            }

            let baseName = suggestedFileName(for: document)
            let uniqueName = resolveCollision(baseName: baseName, in: folderURL, usedNames: &usedFileNames)
            let destinationURL = folderURL.appendingPathComponent(uniqueName)

            do {
                try copyDocument(document, libraryURL: libraryURL, to: destinationURL)
                exportedCount += 1
            } catch {
                logger.error("Failed to export '\(document.title)': \(error.localizedDescription)")
                failures.append(.init(title: document.title, message: error.localizedDescription))
            }
        }

        return ExportDocumentsResult(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            failures: failures
        )
    }

    static func temporaryExportURL(
        for document: DocumentRecord,
        libraryURL: URL
    ) throws -> URL? {
        guard let item = dragExportItem(for: document, libraryURL: libraryURL) else {
            return nil
        }

        return try temporaryExportURLs(for: [item]).first
    }

    static func dragExportItem(
        for document: DocumentRecord,
        libraryURL: URL
    ) -> DragExportItem? {
        guard let sourceURL = sourceURL(for: document, libraryURL: libraryURL) else {
            return nil
        }

        return DragExportItem(
            sourceURL: sourceURL,
            suggestedFileName: suggestedFileName(for: document)
        )
    }

    static func temporaryExportURLs(
        for items: [DragExportItem]
    ) throws -> [URL] {
        guard !items.isEmpty else { return [] }

        let exportDirectory = try createTemporaryExportDirectory()
        var usedFileNames: [String: Int] = [:]
        var exportedURLs: [URL] = []
        exportedURLs.reserveCapacity(items.count)
        do {
            for item in items {
                let uniqueName = resolveCollision(
                    baseName: item.suggestedFileName,
                    in: exportDirectory,
                    usedNames: &usedFileNames
                )
                let destinationURL = exportDirectory.appendingPathComponent(uniqueName)
                try FileManager.default.copyItem(at: item.sourceURL, to: destinationURL)
                exportedURLs.append(destinationURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: exportDirectory)
            throw error
        }

        scheduleTemporaryExportCleanup(for: exportDirectory)
        return exportedURLs
    }

    private static func labelSuffix(for document: DocumentRecord) -> String {
        let sortedLabels = document.labels.sorted { $0.sortOrder < $1.sortOrder }
        return sortedLabels.map(\.name).joined(separator: ", ")
    }

    private static func sourceURL(for document: DocumentRecord, libraryURL: URL) -> URL? {
        guard let storedFilePath = document.storedFilePath,
              DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else {
            return nil
        }

        return DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
    }

    private static func createTemporaryExportDirectory() throws -> URL {
        cleanupStaleTemporaryExports()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docnest-drag-export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func scheduleTemporaryExportCleanup(for directory: URL) {
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func cleanupStaleTemporaryExports() {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docnest-drag-export", isDirectory: true)
        guard let directoryEnumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-(24 * 60 * 60))
        for case let url as URL in directoryEnumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey]),
                  values.isDirectory == true,
                  let creationDate = values.creationDate,
                  creationDate < cutoffDate else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
            directoryEnumerator.skipDescendants()
        }
    }

    private static func copyDocument(
        _ document: DocumentRecord,
        libraryURL: URL,
        to destinationURL: URL
    ) throws {
        guard let sourceURL = sourceURL(for: document, libraryURL: libraryURL) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func sanitizeForFilesystem(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let sanitized = input.components(separatedBy: illegal).joined(separator: "_")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private static func resolveCollision(
        baseName: String,
        in folderURL: URL,
        usedNames: inout [String: Int]
    ) -> String {
        let lowered = baseName.lowercased()

        if usedNames[lowered] == nil
            && !FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(baseName).path) {
            usedNames[lowered] = 1
            return baseName
        }

        let nameWithoutExt = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension

        var counter = (usedNames[lowered] ?? 1) + 1
        var candidate: String
        repeat {
            candidate = "\(nameWithoutExt) (\(counter)).\(ext)"
            counter += 1
        } while FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(candidate).path)

        usedNames[lowered] = counter - 1
        return candidate
    }
}
