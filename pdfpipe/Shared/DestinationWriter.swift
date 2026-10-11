import Foundation
import Darwin

enum DestinationWriter {
    static func save(_ document: URL, destination: Destination) throws -> URL {
        let folder = try destination.resolve()
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return try save(document, to: folder)
    }

    /// Coordination plus exclusive creation protects existing files even under a race.
    static func save(_ document: URL, to folder: URL) throws -> URL {
        guard (try folder.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw PipeError.message("The destination folder is unavailable. Choose it again in PdfPipe.")
        }
        // Open the input before reserving an output path: a missing input must never
        // become a newly created empty output when source and destination coincide.
        let input = try FileHandle(forReadingFrom: document)
        defer { try? input.close() }
        guard (try document.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw PipeError.message("The processed PDF is unavailable.")
        }
        var coordinationError: NSError?
        var outcome: Result<URL, Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { directory in
            outcome = Result {
                let stem = document.deletingPathExtension().lastPathComponent
                for suffix in 0..<1000 {
                    try Task.checkCancellation()
                    let filename = suffix == 0 ? document.lastPathComponent : "\(stem) (\(suffix + 1)).pdf"
                    let target = directory.appendingPathComponent(filename)
                    let descriptor = open(target.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
                    if descriptor < 0 {
                        if errno == EEXIST { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    defer { close(descriptor) }
                    do {
                        while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
                            try Task.checkCancellation()
                            try chunk.withUnsafeBytes { buffer in
                                var offset = 0
                                while offset < buffer.count {
                                    let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                                    if count < 0 {
                                        if errno == EINTR { continue }
                                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                                    }
                                    guard count > 0 else { throw POSIXError(.EIO) }
                                    offset += count
                                }
                            }
                        }
                        try Task.checkCancellation()
                        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                        return target
                    } catch {
                        let saveError = error
                        do { try FileManager.default.removeItem(at: target) }
                        catch {
                            throw PipeError.message("Saving failed and the partial file ‘\(filename)’ could not be removed from ‘\(directory.lastPathComponent)’. Remove it manually before retrying. \(saveError.localizedDescription)")
                        }
                        throw saveError
                    }
                }
                throw PipeError.message("Too many files have this filename. Choose a different name.")
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw PipeError.message("The destination did not complete the save.") }
        return try outcome.get()
    }
}
