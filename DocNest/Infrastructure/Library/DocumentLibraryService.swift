import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let docNestLibrary = UTType("com.kaps.docnest.library")!
}

struct DocumentLibraryManifest: Codable {
    let formatVersion: Int
    let createdAt: Date
}

enum DocumentLibraryService {
    static let packageExtension = "docnestlibrary"
    static let currentFormatVersion = 1

    private static let persistedLibraryPathKey = "selectedLibraryPath"
    private static let launchArgumentSelectedLibraryPath = "-selectedLibraryPath"
    private static let manifestFileName = "library.json"
    private static let requiredDirectories = [
        "Metadata",
        "Originals",
        "Previews",
        "Diagnostics"
    ]

    static func restorePersistedLibraryURL() -> URL? {
        if let launchArgumentLibraryURL = selectedLibraryURL(from: ProcessInfo.processInfo.arguments) {
            return launchArgumentLibraryURL
        }

        guard let path = UserDefaults.standard.string(forKey: persistedLibraryPathKey) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    static func persistLibraryURL(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.standardizedFileURL.path, forKey: persistedLibraryPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: persistedLibraryPathKey)
        }
    }

    static func promptForExistingLibrary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.docNestLibrary]
        panel.prompt = "Open Library"
        panel.message = "Choose an existing DocNest library."

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url?.standardizedFileURL
    }

    static func promptForNewLibraryURL() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "My Documents"
        panel.prompt = "Create Library"
        panel.message = "Choose where the new DocNest library should be created."
        panel.allowedContentTypes = [.docNestLibrary]
        panel.isExtensionHidden = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return normalizedLibraryURL(from: url)
    }

    static func createLibrary(at url: URL) throws -> URL {
        let libraryURL = normalizedLibraryURL(from: url)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        for directory in requiredDirectories {
            try FileManager.default.createDirectory(
                at: libraryURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let manifest = DocumentLibraryManifest(formatVersion: currentFormatVersion, createdAt: .now)
        let manifestData = try JSONEncoder.prettyPrinted.encode(manifest)
        try manifestData.write(to: manifestURL(for: libraryURL), options: .atomic)

        return libraryURL
    }

    static func migrateLibraryIfNeeded(at libraryURL: URL, manifest: DocumentLibraryManifest) throws {
        guard manifest.formatVersion < currentFormatVersion else { return }

        // Future migrations go here, applied in order:
        // if manifest.formatVersion < 2 { ... }

        let updatedManifest = DocumentLibraryManifest(
            formatVersion: currentFormatVersion,
            createdAt: manifest.createdAt
        )
        let data = try JSONEncoder.prettyPrinted.encode(updatedManifest)
        try data.write(to: manifestURL(for: libraryURL), options: .atomic)
    }

    static func validateLibrary(at url: URL) throws -> (URL, DocumentLibraryManifest) {
        let libraryURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        for directory in requiredDirectories {
            let directoryURL = libraryURL.appendingPathComponent(directory, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ValidationError.missingDirectory(directory)
            }
        }

        let manifestData = try Data(contentsOf: manifestURL(for: libraryURL))
        let manifest = try JSONDecoder.libraryManifest.decode(DocumentLibraryManifest.self, from: manifestData)

        return (libraryURL, manifest)
    }

    static func originalsDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Originals", isDirectory: true)
    }

    static func metadataDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Metadata", isDirectory: true)
    }

    static func metadataStoreURL(for libraryURL: URL) -> URL {
        metadataDirectory(for: libraryURL)
            .appendingPathComponent("library")
            .appendingPathExtension("sqlite")
    }

    static func openModelContainer(for libraryURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "DocNestLibrary",
            url: metadataStoreURL(for: libraryURL),
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: DocumentRecord.self,
            LabelTag.self,
            configurations: configuration
        )
    }

    static func selectedLibraryURL(from launchArguments: [String]) -> URL? {
        guard let argumentIndex = launchArguments.firstIndex(of: launchArgumentSelectedLibraryPath) else {
            return nil
        }

        let valueIndex = launchArguments.index(after: argumentIndex)
        guard valueIndex < launchArguments.endIndex else {
            return nil
        }

        let path = launchArguments[valueIndex]
        guard !path.hasPrefix("-") else {
            return nil
        }

        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func normalizedLibraryURL(from url: URL) -> URL {
        guard url.pathExtension != packageExtension else {
            return url.standardizedFileURL
        }

        return url
            .deletingPathExtension()
            .appendingPathExtension(packageExtension)
            .standardizedFileURL
    }

    private static func manifestURL(for libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent(manifestFileName)
    }

    enum ValidationError: LocalizedError {
        case missingDirectory(String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let directory):
                return "The selected library is missing the required \(directory) directory."
            }
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var libraryManifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}