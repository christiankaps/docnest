import Foundation
import Darwin

enum DestinationWriter {
    static func save(_ document: URL, destination: Destination) throws -> URL {
        let folder = try destination.resolve()
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return try save(document, to: folder)
    }

    /// Stage on the destination volume, then atomically publish without replacing any file.
    static func save(_ document: URL, to folder: URL, didWriteChunk: () throws -> Void = {}) throws -> URL {
        guard (try folder.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw PipeError.message("The destination folder is unavailable. Choose it again in PDF Pipe.")
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
                let staging = directory.appendingPathComponent(".pdfpipe-\(UUID().uuidString).partial")
                let descriptor = open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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
                        try didWriteChunk()
                    }
                    try Task.checkCancellation()
                    guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    let stem = document.deletingPathExtension().lastPathComponent
                    for suffix in 0..<1000 {
                        try Task.checkCancellation()
                        let filename = suffix == 0 ? document.lastPathComponent : "\(stem) (\(suffix + 1)).pdf"
                        let target = directory.appendingPathComponent(filename)
                        // Same-volume rename is the commit point. RENAME_EXCL also
                        // protects against another writer winning the filename race.
                        if renamex_np(staging.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
                        if errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    }
                    throw PipeError.message("Too many files have this filename. Choose a different name.")
                } catch {
                    let saveError = error
                    do { try FileManager.default.removeItem(at: staging) }
                    catch {
                        throw PipeError.message("Saving failed and the staging file ‘\(staging.lastPathComponent)’ could not be removed from ‘\(directory.lastPathComponent)’. Remove it manually before retrying. \(saveError.localizedDescription)")
                    }
                    throw saveError
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw PipeError.message("The destination did not complete the save.") }
        return try outcome.get()
    }
}
