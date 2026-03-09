import Foundation
import PDFKit
import SwiftData

struct ImportPDFDocumentsResult {
    struct Failure {
        let fileName: String?
        let message: String
    }

    let importedCount: Int
    let failures: [Failure]

    var hasFailures: Bool {
        !failures.isEmpty
    }

    var summaryMessage: String {
        let importedLine = importedCount == 1
            ? "Imported 1 document."
            : "Imported \(importedCount) documents."

        guard hasFailures else {
            return importedLine
        }

        let failureLines = failures.map { failure in
            if let fileName = failure.fileName {
                return "- \(fileName): \(failure.message)"
            }

            return "- \(failure.message)"
        }

        return ([importedLine, "Some files could not be imported:"] + failureLines)
            .joined(separator: "\n")
    }
}

enum ImportPDFDocumentsUseCase {
    @MainActor
    static func execute(
        urls: [URL],
        into libraryURL: URL,
        using modelContext: ModelContext
    ) -> ImportPDFDocumentsResult {
        var importedRecords: [DocumentRecord] = []
        var failures: [ImportPDFDocumentsResult.Failure] = []

        for url in urls {
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importedAt = Date.now
                let record = try importDocument(
                    from: url,
                    importedAt: importedAt,
                    into: libraryURL
                )
                modelContext.insert(record)
                importedRecords.append(record)
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

            failures.append(
                .init(
                    fileName: nil,
                    message: "The imported metadata could not be saved."
                )
            )

            return ImportPDFDocumentsResult(importedCount: 0, failures: failures)
        }

        return ImportPDFDocumentsResult(
            importedCount: importedRecords.count,
            failures: failures
        )
    }

    private static func importDocument(
        from url: URL,
        importedAt: Date,
        into libraryURL: URL
    ) throws -> DocumentRecord {
        let documentID = UUID()
        let originalFileName = url.lastPathComponent
        let title = normalizedTitle(for: url)
        let pageCount = PDFDocument(url: url)?.pageCount ?? 0
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
            importedAt: importedAt,
            pageCount: pageCount,
            storedFilePath: storedFilePath
        )
    }

    private static func normalizedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}