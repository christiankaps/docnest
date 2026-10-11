import Foundation

/// Only app-owned Open In deliveries may be consumed; external originals stay read-only.
enum InboxDelivery {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    static func owns(_ url: URL, inbox: URL = directory) -> Bool {
        url.isFileURL && url.deletingLastPathComponent().standardizedFileURL == inbox.standardizedFileURL
    }

    static func excludeFromBackup(inbox: URL = directory) throws {
        guard FileManager.default.fileExists(atPath: inbox.path) else { return }
        var folder = inbox
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    static func claim(_ url: URL, into session: URL, inbox: URL = directory) throws -> URL {
        guard owns(url, inbox: inbox) else { return url }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PipeError.message("Open a regular PDF, JPEG, or PNG file.")
        }
        try excludeFromBackup(inbox: inbox)
        let target = session.appendingPathComponent("delivery").appendingPathExtension(url.pathExtension)
        try FileManager.default.moveItem(at: url, to: target)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
        return target
    }

    static func discard(_ url: URL, inbox: URL = directory) throws {
        guard owns(url, inbox: inbox) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Run on backgrounding, after URL delivery callbacks. A launch-time sweep could
    /// delete the very file whose cold-launch Open In callback is still pending.
    static func removeUnclaimed(inbox: URL = directory) throws {
        guard FileManager.default.fileExists(atPath: inbox.path) else { return }
        try excludeFromBackup(inbox: inbox)
        for url in try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) {
            try discard(url, inbox: inbox)
        }
    }
}
