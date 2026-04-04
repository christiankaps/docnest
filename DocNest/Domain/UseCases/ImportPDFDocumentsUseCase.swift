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
        var parts: [String] = []

        if importedCount > 0 {
            parts.append(importedCount == 1 ? "Imported 1 document" : "Imported \(importedCount) documents")
        }

        if hasDuplicates {
            parts.append(duplicates.count == 1 ? "1 duplicate skipped" : "\(duplicates.count) duplicates skipped")
        }

        if hasUnsupportedFiles {
            parts.append(unsupportedFiles.count == 1 ? "1 unsupported file skipped" : "\(unsupportedFiles.count) unsupported files skipped")
        }

        if hasDownloadFailures {
            parts.append(downloadFailures.count == 1 ? "1 download failed" : "\(downloadFailures.count) downloads failed")
        }

        if hasFailures {
            parts.append(failures.count == 1 ? "1 file failed" : "\(failures.count) files failed")
        }

        if parts.isEmpty {
            return "Import complete."
        }

        return parts.joined(separator: ". ") + "."
    }
}

enum ImportPDFDocumentsUseCase {
    private struct ImportMetadata {
        let contentHash: String
        let fileSize: Int64
        let pageCount: Int
        let documentDate: Date?
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
        var failures: [ImportPDFDocumentsResult.Failure] = []
        for url in urls {
            if url.isFileURL {
                if shouldRejectSelfImport(of: url, into: libraryURL) {
                    failures.append(
                        .init(
                            fileName: url.lastPathComponent.isEmpty ? nil : url.lastPathComponent,
                            message: "Items from inside the open DocNest library cannot be imported."
                        )
                    )
                    continue
                }
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

        var zipTempDirectories: [URL] = []
        let resolvedURLs = resolveFileURLs(fileURLs, tempDirectories: &zipTempDirectories) + downloadedTempFiles
        onProgress?(0, resolvedURLs.count)

        let autoAssignedLabelNames = autoAssignLabels
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var importedRecords: [DocumentRecord] = []
        var importedStoredPaths: [String] = []
        var duplicates: [ImportPDFDocumentsResult.Duplicate] = []
        var unsupportedFiles: [ImportPDFDocumentsResult.Unsupported] = []
        var batchHashes: Set<String> = []

        for (index, url) in resolvedURLs.enumerated() {
            defer { onProgress?(index + 1, resolvedURLs.count) }

            if Task.isCancelled { break }

            guard !shouldRejectSelfImport(of: url, into: libraryURL) else {
                failures.append(
                    .init(
                        fileName: url.lastPathComponent.isEmpty ? nil : url.lastPathComponent,
                        message: "Items from inside the open DocNest library cannot be imported."
                    )
                )
                continue
            }

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

        // Clean up temporary files and directories — originals have been copied into the library
        for tempFile in downloadedTempFiles {
            try? FileManager.default.removeItem(at: tempFile)
        }
        for tempDir in zipTempDirectories {
            try? FileManager.default.removeItem(at: tempDir)
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
            isSupportedDocumentURL(url) || isDirectory(url) || isZipFile(url) || isWebURL(url)
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
            documentDate: metadata.documentDate,
            importedAt: importedAt,
            pageCount: metadata.pageCount,
            fileSize: metadata.fileSize,
            contentHash: metadata.contentHash,
            storedFilePath: storedFilePath
        )
        record.fullText = metadata.fullText
        record.ocrCompleted = true
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
        let (fileSize, creationDate, contentHash, pdfDocument) = try await Task.detached(priority: .userInitiated) {
            let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let creationDate = resourceValues.creationDate
            let contentHash = try hashFile(at: fileURL)
            let pdfDocument = PDFDocument(url: fileURL)
            return (fileSize, creationDate, contentHash, pdfDocument)
        }.value

        let pageCount = pdfDocument?.pageCount ?? 0

        // Use OCR-aware extraction (fast path for embedded text, Vision fallback for scanned pages)
        let fullText: String?
        if let pdfDocument {
            fullText = await OCRTextExtractionService.extractText(from: pdfDocument)
        } else {
            fullText = nil
        }

        // Derive document date: prefer a date found in the document content, fall back to file creation date.
        let documentDate: Date?
        if let text = fullText, let extracted = DocumentDateExtractor.extractDate(from: text) {
            documentDate = extracted
        } else {
            documentDate = creationDate
        }

        return ImportMetadata(
            contentHash: contentHash,
            fileSize: fileSize,
            pageCount: pageCount,
            documentDate: documentDate,
            fullText: fullText
        )
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

    /// Expands any directory and zip URLs into their contained PDF files recursively,
    /// passing through individual file URLs unchanged.
    /// Extracted zip contents are placed in temporary directories returned via `tempDirectories`.
    private static func resolveFileURLs(_ urls: [URL], tempDirectories: inout [URL]) -> [URL] {
        var resolved: [URL] = []

        for url in urls {
            if isDirectory(url) {
                resolved.append(contentsOf: enumeratePDFs(in: url))
            } else if isZipFile(url) {
                let accessedSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if accessedSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                if let extractedDir = extractZipFile(at: url) {
                    tempDirectories.append(extractedDir)
                    resolved.append(contentsOf: enumeratePDFs(in: extractedDir))
                }
            } else {
                resolved.append(url)
            }
        }

        return resolved
    }

    /// Recursively enumerates PDF files inside a directory.
    private static func enumeratePDFs(in directoryURL: URL) -> [URL] {
        let accessedSecurityScope = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if isSupportedDocumentURL(fileURL) {
                results.append(fileURL)
            }
        }
        return results
    }

    /// Extracts a zip archive to a temporary directory using the system `ditto` command.
    /// Returns the URL of the temporary directory, or `nil` on failure.
    private static func extractZipFile(at url: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocNestZipImport-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", url.path, tempDir.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }

        return tempDir
    }

    private static func isZipFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return false }
        if let fileType = UTType(filenameExtension: ext) {
            return fileType.conforms(to: .zip)
        }
        return ext.caseInsensitiveCompare("zip") == .orderedSame
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

    private static func shouldRejectSelfImport(of url: URL, into libraryURL: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return DocumentLibraryService.contains(url, inLibrary: libraryURL)
    }

    private static func normalizedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}
