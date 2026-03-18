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

    struct DownloadFailure {
        let url: URL
        let message: String
    }

    struct Failure {
        let fileName: String?
        let message: String
    }

    let importedCount: Int
    let duplicates: [Duplicate]
    let unsupportedFiles: [Unsupported]
    let downloadFailures: [DownloadFailure]
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

    var hasDownloadFailures: Bool {
        !downloadFailures.isEmpty
    }

    var hasUserMessage: Bool {
        hasDuplicates || hasUnsupportedFiles || hasDownloadFailures || hasFailures || hasAutoAssignedLabels
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

        if hasDownloadFailures {
            lines.append(downloadFailures.count == 1 ? "Failed to download 1 URL:" : "Failed to download \(downloadFailures.count) URLs:")
            lines.append(contentsOf: downloadFailures.map { "- \($0.url.absoluteString): \($0.message)" })
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
        // Partition into file URLs and web URLs
        var fileURLs: [URL] = []
        var webURLs: [URL] = []
        for url in urls {
            if url.isFileURL {
                fileURLs.append(url)
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                webURLs.append(url)
            }
        }

        // Download web URLs to temporary files
        var downloadFailures: [ImportPDFDocumentsResult.DownloadFailure] = []
        var downloadedTempFiles: [URL] = []
        for webURL in webURLs {
            if Task.isCancelled { break }
            do {
                let tempFile = try await downloadPDF(from: webURL)
                downloadedTempFiles.append(tempFile)
            } catch {
                downloadFailures.append(.init(url: webURL, message: error.localizedDescription))
            }
        }

        let resolvedURLs = resolveFileURLs(fileURLs) + downloadedTempFiles
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

        // Clean up downloaded temp files — they have been copied into the library
        for tempFile in downloadedTempFiles {
            try? FileManager.default.removeItem(at: tempFile)
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
                downloadFailures: downloadFailures,
                failures: failures,
                autoAssignedLabels: autoAssignedLabelNames
            )
        }

        return ImportPDFDocumentsResult(
            importedCount: importedRecords.count,
            duplicates: duplicates,
            unsupportedFiles: unsupportedFiles,
            downloadFailures: downloadFailures,
            failures: failures,
            autoAssignedLabels: autoAssignedLabelNames
        )
    }

    static func containsImportableDocuments(in urls: [URL]) -> Bool {
        urls.contains { url in
            isSupportedDocumentURL(url) || isDirectory(url) || isWebURL(url)
        }
    }

    /// Returns true for http/https URLs that may point to a downloadable PDF.
    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Downloads a PDF from a web URL to a temporary file.
    /// The caller is responsible for deleting the temp file after import.
    private static func downloadPDF(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(for: URLRequest(url: url))

        // Derive a meaningful filename from the URL or Content-Disposition header
        let suggestedName = suggestedFileName(from: url, response: response)

        let destinationURL = tempURL.deletingLastPathComponent().appendingPathComponent(suggestedName)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }

    private static func suggestedFileName(from url: URL, response: URLResponse) -> String {
        // Try Content-Disposition header first
        if let httpResponse = response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filename = parseFilenameFromContentDisposition(disposition) {
            return filename
        }

        // Fall back to URL path component
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty, lastComponent != "/" {
            let decoded = lastComponent.removingPercentEncoding ?? lastComponent
            // Strip query parameters that may have leaked into the filename
            if let questionMark = decoded.firstIndex(of: "?") {
                let name = String(decoded[decoded.startIndex..<questionMark])
                return name.hasSuffix(".pdf") ? name : name + ".pdf"
            }
            return decoded.hasSuffix(".pdf") ? decoded : decoded + ".pdf"
        }

        return "Downloaded.pdf"
    }

    private static func parseFilenameFromContentDisposition(_ header: String) -> String? {
        // Match filename*=UTF-8''name or filename="name" or filename=name
        let patterns: [String] = [
            "filename\\*=(?:UTF-8|utf-8)''(.+?)(?:;|$)",
            "filename=\"(.+?)\"",
            "filename=([^;\\s]+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: header) {
                let filename = String(header[range]).removingPercentEncoding ?? String(header[range])
                if !filename.isEmpty { return filename }
            }
        }
        return nil
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
            title: title,
            contentHash: metadata.contentHash,
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