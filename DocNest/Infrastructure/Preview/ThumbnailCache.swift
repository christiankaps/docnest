import AppKit
import PDFKit

@MainActor
@Observable
final class ThumbnailCache {
    private(set) var loadedThumbnails: [String: NSImage] = [:]
    private let backingCache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<Void, Never>] = [:]
    private let countLimit: Int

    init(countLimit: Int = 500) {
        self.countLimit = countLimit
        backingCache.countLimit = countLimit
    }

    /// Returns a cached thumbnail immediately, or `nil` while kicking off an
    /// asynchronous load. The `loadedThumbnails` dictionary is `@Observable`-tracked,
    /// so the calling view will re-render once the thumbnail becomes available.
    func thumbnail(for storedFilePath: String, libraryURL: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(storedFilePath: storedFilePath, size: size)

        if let image = loadedThumbnails[key] {
            return image
        }

        if let image = backingCache.object(forKey: key as NSString) {
            loadedThumbnails[key] = image
            return image
        }

        loadThumbnailAsync(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size, key: key)
        return nil
    }

    private func pruneStaleEntries() {
        guard loadedThumbnails.count > countLimit else { return }
        let keysToRemove = loadedThumbnails.keys.filter { key in
            backingCache.object(forKey: key as NSString) == nil
        }
        for key in keysToRemove {
            loadedThumbnails.removeValue(forKey: key)
        }
    }

    private func loadThumbnailAsync(storedFilePath: String, libraryURL: URL, size: CGSize, key: String) {
        guard inFlightTasks[key] == nil else { return }

        let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)

        inFlightTasks[key] = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            guard DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else { return }
            guard let pdfDocument = PDFDocument(url: fileURL),
                  let page = pdfDocument.page(at: 0) else { return }

            let nsImage = page.thumbnail(of: NSSize(width: size.width, height: size.height), for: .mediaBox)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.backingCache.setObject(nsImage, forKey: key as NSString)
                self.loadedThumbnails[key] = nsImage
                self.inFlightTasks.removeValue(forKey: key)
                self.pruneStaleEntries()
            }
        }
    }

    private func cacheKey(storedFilePath: String, size: CGSize) -> String {
        "\(storedFilePath)_\(Int(size.width))x\(Int(size.height))"
    }
}
