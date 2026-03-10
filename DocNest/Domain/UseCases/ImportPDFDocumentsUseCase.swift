import Foundation
import CryptoKit
import PDFKit
import SwiftData

struct ImportPDFDocumentsResult {
    struct Duplicate {
        let fileName: String
    }

    struct Failure {
        let fileName: String?
        let message: String
    }

    let importedCount: Int
    let duplicates: [Duplicate]
    let failures: [Failure]

    var hasDuplicates: Bool {
        !duplicates.isEmpty
    }

    var hasFailures: Bool {
        !failures.isEmpty
    }

    var hasUserMessage: Bool {
        hasDuplicates || hasFailures
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
    }

    @MainActor
    static func execute(
        urls: [URL],
        into libraryURL: URL,
        using modelContext: ModelContext
    ) -> ImportPDFDocumentsResult {
        var importedRecords: [DocumentRecord] = []
        var importedStoredPaths: [String] = []
        var duplicates: [ImportPDFDocumentsResult.Duplicate] = []
        var failures: [ImportPDFDocumentsResult.Failure] = []
        var knownHashes = existingHashes(using: modelContext)

        for url in urls {
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importedAt = Date.now
                let metadata = try importMetadata(for: url)

                if knownHashes.contains(metadata.contentHash) {
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
                importedRecords.append(record)
                if let storedFilePath = record.storedFilePath {
                    importedStoredPaths.append(storedFilePath)
                }
                knownHashes.insert(metadata.contentHash)
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

            return ImportPDFDocumentsResult(importedCount: 0, duplicates: duplicates, failures: failures)
        }

        return ImportPDFDocumentsResult(
            importedCount: importedRecords.count,
            duplicates: duplicates,
            failures: failures
        )
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

        return DocumentRecord(
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
    }

    private static func existingHashes(using modelContext: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<DocumentRecord>()
        let documents = (try? modelContext.fetch(descriptor)) ?? []
        return Set(documents.map(\.contentHash).filter { !$0.isEmpty })
    }

    private static func importMetadata(for url: URL) throws -> ImportMetadata {
        let resourceValues = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let fileData = try Data(contentsOf: url)
        let digest = SHA256.hash(data: fileData)
        let contentHash = digest.compactMap { String(format: "%02x", $0) }.joined()

        return ImportMetadata(
            contentHash: contentHash,
            fileSize: Int64(resourceValues.fileSize ?? fileData.count),
            pageCount: PDFDocument(data: fileData)?.pageCount ?? 0,
            sourceCreatedAt: resourceValues.creationDate
        )
    }

    private static func normalizedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}