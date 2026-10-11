import Foundation
import Darwin

/// An advisory lock prevents cleanup from deleting an active app/extension session.
final class TemporarySession: @unchecked Sendable {
    let directory: URL
    private let descriptor: Int32

    static func root() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PdfPipeAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw PipeError.message("PDF Pipe shared storage is unavailable. Check App Group signing for both targets.")
        }
        return container.appendingPathComponent("Library/Caches/Sessions", isDirectory: true)
    }

    init(root: URL) throws {
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = self.directory
        descriptor = try Self.withMaintenanceLock(root: root) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete])
                var excluded = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try excluded.setResourceValues(values)
                let fd = open(directory.appendingPathComponent("active.lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
                guard fd >= 0 else { throw PipeError.message("Cannot secure temporary document storage.") }
                guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                    close(fd)
                    throw PipeError.message("Cannot lock temporary document storage.")
                }
                return fd
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    private static func withMaintenanceLock<T>(root: URL, _ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent("maintenance.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw PipeError.message("Cannot open the temporary storage lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw PipeError.message("Cannot lock temporary storage for cleanup.") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }

    func cleanup() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    deinit { flock(descriptor, LOCK_UN); close(descriptor) }

    static func removeAbandoned(root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try withMaintenanceLock(root: root) {
            let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            for child in children where UUID(uuidString: child.lastPathComponent) != nil {
                let lock = child.appendingPathComponent("active.lock")
                let fd = open(lock.path, O_RDWR | O_CLOEXEC)
                if fd < 0 {
                    // Creation and cleanup use the same root lock, so an unlocked
                    // partial directory cannot belong to an initializing session.
                    if errno == ENOENT { try FileManager.default.removeItem(at: child) }
                    continue
                }
                defer { close(fd) }
                if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                    defer { flock(fd, LOCK_UN) }
                    try FileManager.default.removeItem(at: child)
                }
            }
        }
    }
}
