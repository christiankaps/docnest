import AppKit
import Foundation
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
        let exportedLine = exportedCount == 1
            ? "Exported 1 document."
            : "Exported \(exportedCount) documents."

        guard hasUserMessage else {
            return exportedLine
        }

        var lines = [exportedLine]

        if skippedCount > 0 {
            lines.append(skippedCount == 1
                ? "Skipped 1 document without a stored file."
                : "Skipped \(skippedCount) documents without stored files.")
        }

        if !failures.isEmpty {
            lines.append(failures.count == 1
                ? "1 document could not be exported:"
                : "\(failures.count) documents could not be exported:")
            lines.append(contentsOf: failures.map { "- \($0.title): \($0.message)" })
        }

        return lines.joined(separator: "\n")
    }
}

enum ExportDocumentsUseCase {

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
    /// Returns a result for bulk export, or `nil` for single-document export (NSSavePanel handles its own UX).
    @MainActor
    static func exportDocuments(
        _ documents: [DocumentRecord],
        libraryURL: URL
    ) -> ExportDocumentsResult? {
        guard !documents.isEmpty else { return nil }

        if documents.count == 1, let document = documents.first {
            exportSingleDocument(document, libraryURL: libraryURL)
            return nil
        }

        return exportMultipleDocuments(documents, libraryURL: libraryURL)
    }

    // MARK: - Private

    @MainActor
    private static func exportSingleDocument(
        _ document: DocumentRecord,
        libraryURL: URL
    ) {
        guard let storedFilePath = document.storedFilePath,
              DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else {
            return
        }

        let sourceURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName(for: document)
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
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

        var exportedCount = 0
        var skippedCount = 0
        var failures: [ExportDocumentsResult.Failure] = []
        var usedFileNames: [String: Int] = [:]

        for document in documents {
            guard let storedFilePath = document.storedFilePath,
                  DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else {
                skippedCount += 1
                continue
            }

            let sourceURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
            let baseName = suggestedFileName(for: document)
            let uniqueName = resolveCollision(baseName: baseName, in: folderURL, usedNames: &usedFileNames)
            let destinationURL = folderURL.appendingPathComponent(uniqueName)

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                exportedCount += 1
            } catch {
                failures.append(.init(title: document.title, message: error.localizedDescription))
            }
        }

        return ExportDocumentsResult(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            failures: failures
        )
    }

    private static func labelSuffix(for document: DocumentRecord) -> String {
        let sortedLabels = document.labels.sorted { $0.sortOrder < $1.sortOrder }
        return sortedLabels.map(\.name).joined(separator: ", ")
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
