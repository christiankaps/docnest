import Foundation
import CryptoKit
import PDFKit
import SwiftData
import UniformTypeIdentifiers

/// Summary of one import run across all supported inputs.
///
/// The result is intentionally count-based so UI surfaces can show concise
/// toasts for batch imports without enumerating filenames.
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
    let hadNoImportablePDFs: Bool
    let autoAssignedLabels: [String]
    let importedDocuments: [DocumentRecord]

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

    var hasNoImportablePDFs: Bool {
        hadNoImportablePDFs
    }

    var hasUserMessage: Bool {
        hasDuplicates || hasUnsupportedFiles || hasDownloadFailures || hasFailures || hasAutoAssignedLabels || hasNoImportablePDFs
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

        if hasNoImportablePDFs {
            parts.append("No PDF documents found to import")
        }

        if parts.isEmpty {
            return "Import complete."
        }

        return parts.joined(separator: ". ") + "."
    }
}

/// Shared import pipeline for PDFs, folders, ZIP archives, and downloadable URLs.
///
/// All user-facing import entry points are expected to route through this use case
/// so duplicate handling, recursive folder expansion, self-import protection,
/// storage behavior, and record creation remain consistent.
enum ImportPDFDocumentsUseCase {
    private static let maximumSourceBytes: Int64 = 512 * 1_024 * 1_024
    private static let maximumExtractedArchiveBytes: Int64 = 1_024 * 1_024 * 1_024
    private static let downloadTimeout: TimeInterval = 60
    private static let maximumResolvedDocumentCandidates = 20_000
    private static let maximumArchiveEntries = 10_000
    private static let maximumArchivePathDepth = 32
    private static let archiveExtractionTimeout: TimeInterval = 60

    private enum ImportValidationError: LocalizedError {
        case fileTooLarge
        case archiveExpandsTooLarge
        case archiveHasTooManyEntries
        case archiveHasUnsafePath
        case archiveTookTooLong
        case tooManyDocumentCandidates
        case invalidDownloadResponse
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "This file exceeds DocNest's 512 MB import limit."
            case .archiveExpandsTooLarge:
                return "This archive expands beyond DocNest's 1 GB safety limit."
            case .archiveHasTooManyEntries:
                return "This archive contains too many entries to import safely."
            case .archiveHasUnsafePath:
                return "This archive contains an unsafe or excessively deep path."
            case .archiveTookTooLong:
                return "This archive took too long to extract and was cancelled."
            case .tooManyDocumentCandidates:
                return "This import contains too many PDF files to process safely."
            case .invalidDownloadResponse:
                return "The download server did not return a successful response."
            case .unreadablePDF:
                return "This file is not a readable PDF document."
            }
        }
    }
    #if DEBUG
    static var resolveFileURLsDidStartForTesting: (() -> Void)?
    static var stagedImportForTesting: (() -> Void)?
    static var commitPreparedImportsDidStartForTesting: (() -> Void)?
    static var savedPreparedImportsForTesting: (() -> Void)?
    static var committedCancellationRollbackSaveForTesting: (() throws -> Void)?
    #endif

    private struct ImportMetadata {
        let contentHash: String
        let fileSize: Int64
        let pageCount: Int
        let documentDate: Date?
    }

    private struct PreparedImport {
        let originalFileName: String
        let title: String
        let documentDate: Date?
        let importedAt: Date
        let pageCount: Int
        let fileSize: Int64
        let contentHash: String
        let storedFilePath: String
    }

    private struct ResolvedFileURLs {
        let urls: [URL]
        let tempDirectories: [URL]
        let failures: [ImportPDFDocumentsResult.Failure]
    }

    /// Resolves the supplied URLs, imports all supported PDFs into the active
    /// library package, and creates `DocumentRecord` entries for successfully
    /// staged documents.
    ///
    /// The method expands folders and ZIP archives recursively, downloads web
    /// URLs to temporary files, rejects files from inside the open library, and
    /// reports a count-based summary of imported, skipped, and failed work.
    static func execute(
        urls: [URL],
        into libraryURL: URL,
        autoAssignLabels: [LabelTag] = [],
        existingContentHashes: Set<String> = [],
        using modelContext: ModelContext,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> ImportPDFDocumentsResult {
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

        var downloadFailures: [ImportPDFDocumentsResult.DownloadFailure] = []
        var downloadedTempFiles: [URL] = []
        var downloadedTempDirectories: [URL] = []
        for webURL in webURLs {
            if Task.isCancelled { break }
            do {
                let downloadedFile = try await downloadPDF(from: webURL)
                downloadedTempDirectories.append(downloadedFile.temporaryDirectory)
                downloadedTempFiles.append(downloadedFile.fileURL)
            } catch {
                downloadFailures.append(.init(url: webURL, message: error.localizedDescription))
            }
        }

        let resolvedFileURLs = await resolveFileURLsAsync(fileURLs)
        let zipTempDirectories = resolvedFileURLs.tempDirectories
        let resolvedURLs = resolvedFileURLs.urls + downloadedTempFiles
        failures.append(contentsOf: resolvedFileURLs.failures)

        if Task.isCancelled {
            for tempDirectory in downloadedTempDirectories {
                try? FileManager.default.removeItem(at: tempDirectory)
            }
            for tempDir in zipTempDirectories {
                try? FileManager.default.removeItem(at: tempDir)
            }
            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: [],
                unsupportedFiles: [],
                downloadFailures: downloadFailures,
                failures: failures,
                hadNoImportablePDFs: false,
                autoAssignedLabels: [],
                importedDocuments: []
            )
        }

        let hadNoImportablePDFs = resolvedURLs.isEmpty && !fileURLs.isEmpty && failures.isEmpty
        if let onProgress {
            await onProgress(0, resolvedURLs.count)
        }

        let autoAssignedLabelNames = autoAssignLabels
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let knownContentHashesSeed = existingContentHashes
            .union(await persistedContentHashes(using: modelContext))
            .union(await pendingContentHashes(using: modelContext))
        var preparedImports: [PreparedImport] = []
        var duplicates: [ImportPDFDocumentsResult.Duplicate] = []
        var unsupportedFiles: [ImportPDFDocumentsResult.Unsupported] = []
        var knownContentHashes = knownContentHashesSeed

        for (index, url) in resolvedURLs.enumerated() {
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
                let preparedImport = try await prepareImport(
                    from: url,
                    importedAt: importedAt
                )

                if knownContentHashes.contains(preparedImport.contentHash) {
                    duplicates.append(.init(fileName: url.lastPathComponent))
                } else {
                    let stagedImport = try stagePreparedImport(
                        preparedImport,
                        from: url,
                        into: libraryURL
                    )
                    preparedImports.append(stagedImport)
                    knownContentHashes.insert(preparedImport.contentHash)
                    #if DEBUG
                    stagedImportForTesting?()
                    #endif
                }
            } catch {
                failures.append(
                    .init(
                        fileName: url.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }

            if let onProgress {
                await onProgress(index + 1, resolvedURLs.count)
            }
        }

        if Task.isCancelled {
            for preparedImport in preparedImports {
                DocumentStorageService.deleteStoredFile(at: preparedImport.storedFilePath, libraryURL: libraryURL)
            }
            for tempDirectory in downloadedTempDirectories {
                try? FileManager.default.removeItem(at: tempDirectory)
            }
            for tempDir in zipTempDirectories {
                try? FileManager.default.removeItem(at: tempDir)
            }
            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: [],
                unsupportedFiles: [],
                downloadFailures: downloadFailures,
                failures: failures,
                hadNoImportablePDFs: false,
                autoAssignedLabels: [],
                importedDocuments: []
            )
        }

        for tempDirectory in downloadedTempDirectories {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        for tempDir in zipTempDirectories {
            try? FileManager.default.removeItem(at: tempDir)
        }

        return await commitPreparedImports(
            preparedImports,
            autoAssignLabels: autoAssignLabels,
            into: modelContext,
            libraryURL: libraryURL,
            duplicates: duplicates,
            unsupportedFiles: unsupportedFiles,
            downloadFailures: downloadFailures,
            failures: failures,
            hadNoImportablePDFs: hadNoImportablePDFs,
            autoAssignedLabelNames: autoAssignedLabelNames
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

    private struct DownloadedFile {
        let fileURL: URL
        let temporaryDirectory: URL
    }

    /// Downloads a PDF into a private temporary directory.
    /// The caller is responsible for deleting that directory after import.
    private static func downloadPDF(from url: URL) async throws -> DownloadedFile {
        var request = URLRequest(url: url)
        request.timeoutInterval = downloadTimeout
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ImportValidationError.invalidDownloadResponse
            }
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength <= maximumSourceBytes else {
            throw ImportValidationError.fileTooLarge
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocNestDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let tempURL = temporaryDirectory.appendingPathComponent("download.partial", isDirectory: false)
        guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: tempURL)
        var didSucceed = false
        defer {
            try? handle.close()
            if !didSucceed {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
        }

        var byteCount: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1_024)
        for try await byte in bytes {
            try Task.checkCancellation()
            byteCount += 1
            guard byteCount <= maximumSourceBytes else {
                throw ImportValidationError.fileTooLarge
            }
            buffer.append(byte)
            if buffer.count == 64 * 1_024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        // Derive a meaningful filename from the URL or Content-Disposition header
        let suggestedName = safeDownloadFileName(suggestedFileName(from: url, response: response))

        let destinationURL = temporaryDirectory.appendingPathComponent(suggestedName)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        didSucceed = true
        return DownloadedFile(fileURL: destinationURL, temporaryDirectory: temporaryDirectory)
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

    private static func safeDownloadFileName(_ proposedName: String) -> String {
        let name = URL(fileURLWithPath: proposedName).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return "Downloaded.pdf" }
        return name.hasSuffix(".pdf") ? name : name + ".pdf"
    }

    private static let contentDispositionFilenameRegexes: [NSRegularExpression] = {
        let patterns = [
            "filename\\*=(?:UTF-8|utf-8)''(.+?)(?:;|$)",
            "filename=\"(.+?)\"",
            "filename=([^;\\s]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static func parseFilenameFromContentDisposition(_ header: String) -> String? {
        for regex in contentDispositionFilenameRegexes {
            if let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: header) {
                let filename = String(header[range]).removingPercentEncoding ?? String(header[range])
                if !filename.isEmpty { return filename }
            }
        }
        return nil
    }

    private static func prepareImport(
        from url: URL,
        importedAt: Date
    ) async throws -> PreparedImport {
        let metadata = try await importMetadata(for: url)
        let originalFileName = url.lastPathComponent
        let title = normalizedTitle(for: url)

        return PreparedImport(
            originalFileName: originalFileName,
            title: title,
            documentDate: metadata.documentDate,
            importedAt: importedAt,
            pageCount: metadata.pageCount,
            fileSize: metadata.fileSize,
            contentHash: metadata.contentHash,
            storedFilePath: ""
        )
    }

    private static func stagePreparedImport(
        _ preparedImport: PreparedImport,
        from sourceURL: URL,
        into libraryURL: URL
    ) throws -> PreparedImport {
        let storedFilePath = try DocumentStorageService.copyToStorage(
            from: sourceURL,
            title: preparedImport.title,
            contentHash: preparedImport.contentHash,
            importedAt: preparedImport.importedAt,
            libraryURL: libraryURL
        )

        return PreparedImport(
            originalFileName: preparedImport.originalFileName,
            title: preparedImport.title,
            documentDate: preparedImport.documentDate,
            importedAt: preparedImport.importedAt,
            pageCount: preparedImport.pageCount,
            fileSize: preparedImport.fileSize,
            contentHash: preparedImport.contentHash,
            storedFilePath: storedFilePath
        )
    }

    @MainActor
    private static func persistedContentHashes(using modelContext: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<DocumentRecord>()
        let savedDocuments = (try? modelContext.fetch(descriptor)) ?? []
        return Set(savedDocuments.lazy.map(\.contentHash))
    }

    @MainActor
    private static func pendingContentHashes(using modelContext: ModelContext) -> Set<String> {
        let stagedDocuments = (modelContext.insertedModelsArray + modelContext.changedModelsArray)
            .compactMap { $0 as? DocumentRecord }
        return Set(stagedDocuments.lazy.map(\.contentHash))
    }

    @MainActor
    private static func commitPreparedImports(
        _ preparedImports: [PreparedImport],
        autoAssignLabels: [LabelTag],
        into modelContext: ModelContext,
        libraryURL: URL,
        duplicates: [ImportPDFDocumentsResult.Duplicate],
        unsupportedFiles: [ImportPDFDocumentsResult.Unsupported],
        downloadFailures: [ImportPDFDocumentsResult.DownloadFailure],
        failures: [ImportPDFDocumentsResult.Failure],
        hadNoImportablePDFs: Bool,
        autoAssignedLabelNames: [String]
    ) -> ImportPDFDocumentsResult {
        var importedRecords: [DocumentRecord] = []
        var importedStoredPaths: [String] = []
        var failures = failures

        #if DEBUG
        commitPreparedImportsDidStartForTesting?()
        #endif

        guard !Task.isCancelled else {
            for preparedImport in preparedImports {
                DocumentStorageService.deleteStoredFile(at: preparedImport.storedFilePath, libraryURL: libraryURL)
            }
            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: duplicates,
                unsupportedFiles: unsupportedFiles,
                downloadFailures: downloadFailures,
                failures: failures,
                hadNoImportablePDFs: false,
                autoAssignedLabels: [],
                importedDocuments: []
            )
        }

        for preparedImport in preparedImports {
            let record = DocumentRecord(
                originalFileName: preparedImport.originalFileName,
                title: preparedImport.title,
                documentDate: preparedImport.documentDate,
                importedAt: preparedImport.importedAt,
                pageCount: preparedImport.pageCount,
                fileSize: preparedImport.fileSize,
                contentHash: preparedImport.contentHash,
                storedFilePath: preparedImport.storedFilePath
            )
            record.fullText = nil
            record.ocrCompleted = false
            record.labels = autoAssignLabels
            modelContext.insert(record)
            importedRecords.append(record)
            importedStoredPaths.append(preparedImport.storedFilePath)
        }

        guard !Task.isCancelled else {
            for record in importedRecords {
                modelContext.delete(record)
            }
            for storedFilePath in importedStoredPaths {
                DocumentStorageService.deleteStoredFile(at: storedFilePath, libraryURL: libraryURL)
            }
            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: duplicates,
                unsupportedFiles: unsupportedFiles,
                downloadFailures: downloadFailures,
                failures: failures,
                hadNoImportablePDFs: false,
                autoAssignedLabels: [],
                importedDocuments: []
            )
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
                hadNoImportablePDFs: hadNoImportablePDFs,
                autoAssignedLabels: autoAssignedLabelNames,
                importedDocuments: []
            )
        }

        #if DEBUG
        savedPreparedImportsForTesting?()
        #endif

        if Task.isCancelled {
            for record in importedRecords {
                modelContext.delete(record)
            }
            do {
                #if DEBUG
                if let committedCancellationRollbackSaveForTesting {
                    try committedCancellationRollbackSaveForTesting()
                } else {
                    try modelContext.save()
                }
                #else
                try modelContext.save()
                #endif
                for storedFilePath in importedStoredPaths {
                    DocumentStorageService.deleteStoredFile(at: storedFilePath, libraryURL: libraryURL)
                }
            } catch {
                modelContext.rollback()
                failures.append(
                    .init(
                        fileName: nil,
                        message: "The cancelled import could not be rolled back."
                    )
                )
                return ImportPDFDocumentsResult(
                    importedCount: importedRecords.count,
                    duplicates: duplicates,
                    unsupportedFiles: unsupportedFiles,
                    downloadFailures: downloadFailures,
                    failures: failures,
                    hadNoImportablePDFs: hadNoImportablePDFs,
                    autoAssignedLabels: autoAssignedLabelNames,
                    importedDocuments: importedRecords
                )
            }
            return ImportPDFDocumentsResult(
                importedCount: 0,
                duplicates: duplicates,
                unsupportedFiles: unsupportedFiles,
                downloadFailures: downloadFailures,
                failures: failures,
                hadNoImportablePDFs: false,
                autoAssignedLabels: [],
                importedDocuments: []
            )
        }

        return ImportPDFDocumentsResult(
            importedCount: importedRecords.count,
            duplicates: duplicates,
            unsupportedFiles: unsupportedFiles,
            downloadFailures: downloadFailures,
            failures: failures,
            hadNoImportablePDFs: hadNoImportablePDFs,
            autoAssignedLabels: autoAssignedLabelNames,
            importedDocuments: importedRecords
        )
    }

    private static func importMetadata(for url: URL) async throws -> ImportMetadata {
        let fileURL = url
        let (fileSize, creationDate, contentHash, pdfDocument) = try await Task.detached(priority: .userInitiated) {
            let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            guard fileSize <= maximumSourceBytes else {
                throw ImportValidationError.fileTooLarge
            }
            let creationDate = resourceValues.creationDate
            let contentHash = try hashFile(at: fileURL)
            let pdfDocument = PDFDocument(url: fileURL)
            return (fileSize, creationDate, contentHash, pdfDocument)
        }.value

        guard let pdfDocument, !pdfDocument.isLocked, pdfDocument.pageCount > 0 else {
            throw ImportValidationError.unreadablePDF
        }
        let pageCount = pdfDocument.pageCount

        return ImportMetadata(
            contentHash: contentHash,
            fileSize: fileSize,
            pageCount: pageCount,
            documentDate: creationDate
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
    private static func resolveFileURLsAsync(_ urls: [URL]) async -> ResolvedFileURLs {
        let resolverTask = Task.detached(priority: .utility) {
            #if DEBUG
            resolveFileURLsDidStartForTesting?()
            #endif

            var tempDirectories: [URL] = []
            do {
                let result = try resolveFileURLs(urls, tempDirectories: &tempDirectories)
                return ResolvedFileURLs(
                    urls: result.urls,
                    tempDirectories: tempDirectories,
                    failures: result.failures
                )
            } catch is CancellationError {
                for tempDirectory in tempDirectories {
                    try? FileManager.default.removeItem(at: tempDirectory)
                }
                return ResolvedFileURLs(urls: [], tempDirectories: [], failures: [])
            } catch {
                return ResolvedFileURLs(
                    urls: [],
                    tempDirectories: tempDirectories,
                    failures: [.init(fileName: nil, message: error.localizedDescription)]
                )
            }
        }

        return await withTaskCancellationHandler {
            await resolverTask.value
        } onCancel: {
            resolverTask.cancel()
        }
    }

    private static func resolveFileURLs(
        _ urls: [URL],
        tempDirectories: inout [URL]
    ) throws -> (urls: [URL], failures: [ImportPDFDocumentsResult.Failure]) {
        var resolved: [URL] = []
        var failures: [ImportPDFDocumentsResult.Failure] = []

        for url in urls {
            try Task.checkCancellation()
            do {
                if isDirectory(url) {
                    resolved.append(contentsOf: try enumeratePDFs(in: url) {
                        try Task.checkCancellation()
                    })
                } else if isZipFile(url) {
                    let accessedSecurityScope = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessedSecurityScope {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    let extractedDir = try extractZipFile(at: url)
                    tempDirectories.append(extractedDir)
                    resolved.append(contentsOf: try enumeratePDFs(in: extractedDir) {
                        try Task.checkCancellation()
                    })
                } else {
                    resolved.append(url)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(.init(fileName: url.lastPathComponent, message: error.localizedDescription))
            }
        }

        return (resolved, failures)
    }

    /// Recursively enumerates PDF files inside a directory.
    /// Recursively enumerates PDF files inside a directory while skipping hidden
    /// files and package descendants.
    ///
    /// This helper is used both for direct folder imports and for watch-folder
    /// recursive scanning so nested-folder behavior stays aligned.
    static func enumeratePDFs(
        in directoryURL: URL,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws -> [URL] {
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
        var index = 0
        for case let fileURL as URL in enumerator {
            if index.isMultiple(of: 64) {
                try cancellationCheck?()
            }
            if isSupportedDocumentURL(fileURL) {
                guard results.count < maximumResolvedDocumentCandidates else {
                    throw ImportValidationError.tooManyDocumentCandidates
                }
                results.append(fileURL)
            }
            index += 1
        }
        return results
    }

    /// Extracts a zip archive to a temporary directory using the system `ditto` command.
    /// Returns the URL of the temporary directory or throws a user-visible
    /// validation/error result that the resolver preserves in the import summary.
    private static func extractZipFile(at url: URL) throws -> URL {
        let archiveSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard archiveSize <= maximumSourceBytes else {
            throw ImportValidationError.fileTooLarge
        }
        try preflightZipArchive(at: url)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocNestZipImport-\(UUID().uuidString)", isDirectory: true)

        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", url.path, tempDir.path]

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(archiveExtractionTimeout)
            while process.isRunning {
                try Task.checkCancellation()
                if Date() >= deadline {
                    process.terminate()
                    process.waitUntilExit()
                    try? FileManager.default.removeItem(at: tempDir)
                    throw ImportValidationError.archiveTookTooLong
                }
                if directorySize(at: tempDir) > maximumExtractedArchiveBytes {
                    process.terminate()
                    process.waitUntilExit()
                    try? FileManager.default.removeItem(at: tempDir)
                    throw ImportValidationError.archiveExpandsTooLarge
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch is CancellationError {
            if process.isRunning {
                process.terminate()
            }
            try? FileManager.default.removeItem(at: tempDir)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            throw CocoaError(.fileReadCorruptFile)
        }

        return tempDir
    }

    /// Preflights ZIP entry names before extraction so an archive cannot create
    /// an unbounded or traversal-shaped filesystem tree inside temporary storage.
    private static func preflightZipArchive(at url: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let handle = output.fileHandleForReading
        var pending = Data()
        var entryCount = 0
        while true {
            let data = try handle.read(upToCount: 4_096) ?? Data()
            if data.isEmpty { break }
            pending.append(data)
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let line = pending.prefix(upTo: newlineIndex)
                pending.removeSubrange(...newlineIndex)
                try validateArchiveEntry(String(decoding: line, as: UTF8.self), count: &entryCount)
            }
            try Task.checkCancellation()
        }
        if !pending.isEmpty {
            try validateArchiveEntry(String(decoding: pending, as: UTF8.self), count: &entryCount)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func validateArchiveEntry(_ entry: String, count: inout Int) throws {
        count += 1
        guard count <= maximumArchiveEntries else {
            throw ImportValidationError.archiveHasTooManyEntries
        }
        let normalizedEntry = entry.hasSuffix("/") ? String(entry.dropLast()) : entry
        let components = normalizedEntry.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalizedEntry.isEmpty,
              !normalizedEntry.hasPrefix("/"),
              components.count <= maximumArchivePathDepth,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ImportValidationError.archiveHasUnsafePath
        }
    }

    private static func directorySize(at directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if total > maximumExtractedArchiveBytes { return total }
        }
        return total
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

    private static func shouldRejectSelfImport(
        of url: URL,
        into libraryURL: URL
    ) -> Bool {
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
