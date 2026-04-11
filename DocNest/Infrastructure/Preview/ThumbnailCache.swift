import AppKit
import PDFKit

@MainActor
@Observable
final class ThumbnailCache {
    private(set) var readyThumbnailKeys: Set<String> = []
    private let backingCache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<Void, Never>] = [:]
    private let countLimit: Int

    init(countLimit: Int = 500) {
        self.countLimit = countLimit
        backingCache.countLimit = countLimit
    }

    /// Returns a cached thumbnail immediately, or `nil` while kicking off an
    /// asynchronous load. The `readyThumbnailKeys` set is `@Observable`-tracked,
    /// so the calling view will re-render once the thumbnail becomes available.
    func thumbnail(for storedFilePath: String, libraryURL: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(storedFilePath: storedFilePath, size: size)

        if let image = backingCache.object(forKey: key as NSString) {
            return image
        }

        if readyThumbnailKeys.contains(key) {
            readyThumbnailKeys.remove(key)
        }

        loadThumbnailAsync(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size, key: key)
        return nil
    }

    func cancelAllInFlightTasks() {
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
    }

    private func loadThumbnailAsync(storedFilePath: String, libraryURL: URL, size: CGSize, key: String) {
        guard inFlightTasks[key] == nil else { return }

        let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)

        inFlightTasks[key] = Task.detached(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightTasks.removeValue(forKey: key)
                }
            }

            guard !Task.isCancelled else { return }
            guard DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else { return }
            guard let pdfDocument = PDFDocument(url: fileURL),
                  let page = pdfDocument.page(at: 0) else { return }

            let nsImage = page.thumbnail(of: NSSize(width: size.width, height: size.height), for: .mediaBox)
            guard let imageData = nsImage.tiffRepresentation else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let cachedImage = NSImage(data: imageData) else { return }
                self.backingCache.setObject(cachedImage, forKey: key as NSString)
                self.readyThumbnailKeys.insert(key)
            }
        }
    }

    private func cacheKey(storedFilePath: String, size: CGSize) -> String {
        "\(storedFilePath)_\(Int(size.width))x\(Int(size.height))"
    }
}
