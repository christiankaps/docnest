import Foundation

struct DocumentDate: Codable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!
        month = parts.month!
        day = parts.day!
    }

    var displayDate: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    var isValid: Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day
    }
}

struct LibraryDocument: Codable, Identifiable, Hashable, Sendable {
    enum DateSource: String, Codable, Sendable { case importFallback, manual }
    enum ReviewState: String, Codable, Sendable { case inbox, reviewed }
    enum ProcessingState: String, Codable, Sendable { case notStarted }

    let schemaVersion: Int
    let id: UUID
    var filename: String
    let contentHash: String
    let byteCount: Int64
    let pageCount: Int
    var documentDate: DocumentDate
    var dateSource: DateSource
    let importedAt: Date
    var reviewState: ReviewState
    let processingState: ProcessingState

    // Assignments live in organization.json, never in original import metadata.
    var labelIDs: Set<UUID> = []
    var deletedAt: Date?
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, filename, contentHash, byteCount, pageCount, documentDate,
             dateSource, importedAt, reviewState, processingState
    }

    var title: String { (filename as NSString).deletingPathExtension }
}

struct ImportResult: Sendable {
    let document: LibraryDocument
    let isDuplicate: Bool
}

struct PDFSearchHit: Identifiable, Sendable {
    let id = UUID()
    let pageIndex: Int
    let range: NSRange
    let snippet: String
}

enum LibraryError: LocalizedError, Equatable {
    case encryptedPDF, invalidPDF, invalidLibrary, unsupportedVersion, notLoaded, missingDocument, invalidLabel, invalidDate, invalidFilename, libraryLocked, invalidCapture, invalidCaptureSource

    var errorDescription: String? {
        switch self {
        case .libraryLocked: String(localized: "Unlock your library to continue.")
        case .invalidCaptureSource: String(localized: "Choose an incoming PDF copy outside DocNest’s private storage.")
        case .invalidCapture: String(localized: "A pending capture couldn’t be read safely. Its files have been kept for retry.")
        case .invalidFilename: String(localized: "Enter a nonempty document filename.")
        case .invalidLabel: String(localized: "Use a unique, nonempty label name.")
        case .invalidDate: String(localized: "Choose a valid document date.")
        case .encryptedPDF: String(localized: "Encrypted PDFs aren’t supported. Import an unencrypted copy.")
        case .invalidPDF: String(localized: "This file isn’t a readable PDF. Choose another copy.")
        case .invalidLibrary: String(localized: "The library couldn’t be read safely. Your saved files have been left in place.")
        case .unsupportedVersion: String(localized: "This library was created by a newer version of DocNest. Update the app to open it.")
        case .notLoaded: String(localized: "Open the library before importing a document.")
        case .missingDocument: String(localized: "This document is no longer available.")
        }
    }
}
