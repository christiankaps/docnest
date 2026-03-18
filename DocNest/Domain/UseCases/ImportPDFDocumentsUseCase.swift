import Foundation
import CryptoKit
import PDFKit
import SwiftData
import UniformTypeIdentifiers

struct ImportPDFDocumentsResult {
    struct Duplicate {
        let fileName: String
    }

    struct Unsupported {
        let fileName: String
    }

    struct Failure {
        let fileName: String?
        let message: String
    }

    let importedCount: Int
    let duplicates: [Duplicate]
    let unsupportedFiles: [Unsupported]
    let failures: [Failure]
    let autoAssignedLabels: [String]

    var hasDuplicates: Bool {
        !duplicates.isEmpty
    }

    var hasUnsupportedFiles: Bool {
        !unsupportedFiles.isEmpty
    }

    var hasFailures: Bool {
        !failures.isEmpty
    }

    var hasAutoAssignedLabels: Bool {
        importedCount > 0 && !autoAssignedLabels.isEmpty
    }

    var hasUserMessage: Bool {
        hasDuplicates || hasUnsupportedFiles || hasFailures || hasAutoAssignedLabels
    }

    var summaryMessage: String {
        let importedLine = importedCount == 1
            ? "Imported 1 document."
            : "Imported \(importedCount) documents."

        guard hasUserMessage else {
            return importedLine
        }

        var lines = [importedLine]

        if hasDuplicates {
            lines.append(duplicates.count == 1 ? "Skipped 1 duplicate:" : "Skipped \(duplicates.count) duplicates:")
            lines.append(contentsOf: duplicates.map { "- \($0.fileName)" })
        }

        if hasUnsupportedFiles {
            lines.append(unsupportedFiles.count == 1 ? "Skipped 1 unsupported file:" : "Skipped \(unsupportedFiles.count) unsupported files:")
            lines.append(contentsOf: unsupportedFiles.map { "- \($0.fileName)" })
        }

        if hasAutoAssignedLabels {
            lines.append("Automatically assigned labels: \(autoAssignedLabels.joined(separator: ", ")).")
        }

        let failureLines = failures.map { failure in
            if let fileName = failure.fileName {
                return "- \(fileName): \(failure.message)"
            }

            return "- \(failure.message)"
        }

        if hasFailures {
            lines.append("Some files could not be imported:")
            lines.append(contentsOf: failureLines)
        }

        return lines.joined(separator: "\n")
    }
}

enum ImportPDFDocumentsUseCase {
    private struct ImportMetadata {
        let contentHash: String
        let fileSize: Int64
        let pageCount: Int
        let sourceCreatedAt: Date?
        let fullText: String?
    }

    @MainActor
    static func execute(
        urls: [URL],
        into libraryURL: URL,
        autoAssignLabels: [LabelTag] = [],
        using modelContext: ModelContext,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> ImportPDFDocumentsResult {
        let resolvedURLs = resolveFileURLs(urls)
        onProgress?(0, resolvedURLs.count)

        let autoAssignedLabelNames = autoAssignLabels
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var importedRecords: [DocumentRecord] = []
        var importedStoredPaths: [String] = []
        var duplicates: [ImportPDFDocumentsResult.Duplicate] = []
        var unsupportedFiles: [ImportPDFDocumentsResult.Unsupported] = []
        var failures: [ImportPDFDocumentsResult.Failure] = []
        var batchHashes: Set<String> = []

        for (index, url) in resolvedURLs.enumerated() {
            defer { onProgress?(index + 1, resolvedURLs.count) }

            if Task.isCancelled { break }

            guard isSupportedDocumentURL(url) else {
                unsupportedFiles.append(.init(fileName: url.lastPathComponent))
                continue
            }

            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importedAt = Date.now
                let metadata = try await importMetadata(for: url)

                if batchHashes.contains(metadata.contentHash) || documentExists(withContentHash: metadata.contentHash, using: modelContext) {
                    duplicates.append(.init(fileName: url.lastPathComponent))
                    continue
                }

                let record = try importDocument(
                    from: url,
                    metadata: metadata,
                    importedAt: importedAt,
                    into: libraryURL
                )
                modelContext.insert(record)
                record.labels = autoAssignLabels
                importedRecords.append(record)
                if let storedFilePath = record.storedFilePath {
                    importedStoredPaths.append(storedFilePath)
                }
                batchHashes.insert(metadata.contentHash)
            } catch {
                failures.append(
                    .init(
                        fileName: url.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }

        do {
            try modelContext.save()
        } catch {
            for record in importedRecords {
                modelContext.delete(record)
            }

            for storedFilePath in importedStoredPaths {
                DocumentStorageService.deleteStoredFile(at: storedFilePath, libraryURL: libraryURL)
            }

            failures.append(
                .init(
                    fileName: nil,
                    message: "The imported metadata could not be saved."
                )
            )

            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: duplicates,
                unsupportedFiles: unsupportedFiles,
                failures: failures,
                autoAssignedLabels: autoAssignedLabelNames
            )
        }

        return ImportPDFDocumentsResult(
            importedCount: importedRecords.count,
            duplicates: duplicates,
            unsupportedFiles: unsupportedFiles,
            failures: failures,
            autoAssignedLabels: autoAssignedLabelNames
        )
    }

    static func containsImportableDocuments(in urls: [URL]) -> Bool {
        urls.contains { url in
            isSupportedDocumentURL(url) || isDirectory(url)
        }
    }

    private static func importDocument(
        from url: URL,
        metadata: ImportMetadata,
        importedAt: Date,
        into libraryURL: URL
    ) throws -> DocumentRecord {
        let documentID = UUID()
        let originalFileName = url.lastPathComponent
        let title = normalizedTitle(for: url)
        let storedFilePath = try DocumentStorageService.copyToStorage(
            from: url,
            documentID: documentID,
            importedAt: importedAt,
            libraryURL: libraryURL
        )

        let record = DocumentRecord(
            id: documentID,
            originalFileName: originalFileName,
            title: title,
            sourceCreatedAt: metadata.sourceCreatedAt,
            importedAt: importedAt,
            pageCount: metadata.pageCount,
            fileSize: metadata.fileSize,
            contentHash: metadata.contentHash,
            storedFilePath: storedFilePath
        )
        record.fullText = metadata.fullText
        return record
    }

    private static func documentExists(withContentHash contentHash: String, using modelContext: ModelContext) -> Bool {
        let predicate = #Predicate<DocumentRecord> { document in
            document.contentHash == contentHash
        }
        let descriptor = FetchDescriptor<DocumentRecord>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    private static func importMetadata(for url: URL) async throws -> ImportMetadata {
        let fileURL = url
        return try await Task.detached(priority: .userInitiated) {
            let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let contentHash = try hashFile(at: fileURL)
            let pdfDocument = PDFDocument(url: fileURL)
            let pageCount = pdfDocument?.pageCount ?? 0
            let fullText = extractText(from: pdfDocument)

            return ImportMetadata(
                contentHash: contentHash,
                fileSize: Int64(resourceValues.fileSize ?? 0),
                pageCount: pageCount,
                sourceCreatedAt: resourceValues.creationDate,
                fullText: fullText
            )
        }.value
    }

    private static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Expands any directory URLs into their contained PDF files recursively,
    /// passing through individual file URLs unchanged.
    private static func resolveFileURLs(_ urls: [URL]) -> [URL] {
        var resolved: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            if isDirectory(url) {
                let accessedSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if accessedSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    if isSupportedDocumentURL(fileURL) {
                        resolved.append(fileURL)
                    }
                }
            } else {
                resolved.append(url)
            }
        }

        return resolved
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isSupportedDocumentURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let pathExtension = url.pathExtension
        guard !pathExtension.isEmpty else {
            return false
        }

        if let fileType = UTType(filenameExtension: pathExtension) {
            return fileType.conforms(to: .pdf)
        }

        return pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
    }

    static func extractText(from pdfDocument: PDFDocument?) -> String? {
        guard let pdfDocument, pdfDocument.pageCount > 0 else { return nil }
        var pages: [String] = []
        for index in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: index), let text = page.string, !text.isEmpty {
                pages.append(text)
            }
        }
        return pages.isEmpty ? nil : pages.joined(separator: "\n")
    }

    private static func normalizedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}