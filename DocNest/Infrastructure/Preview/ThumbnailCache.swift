import AppKit
import PDFKit

@MainActor
@Observable
final class ThumbnailCache: NSObject, NSCacheDelegate {
    private final class ThumbnailEntry: NSObject {
        let key: String
        let image: NSImage

        init(key: String, image: NSImage) {
            self.key = key
            self.image = image
        }
    }

    private(set) var readyThumbnailRevisions: [String: Int] = [:]
    private let backingCache = NSCache<NSString, ThumbnailEntry>()
    private var inFlightTasks: [String: Task<Void, Never>] = [:]
    private let countLimit: Int

    init(countLimit: Int = 500) {
        self.countLimit = countLimit
        super.init()
        backingCache.countLimit = countLimit
        backingCache.totalCostLimit = countLimit * 512 * 1024
        backingCache.delegate = self
    }

    /// Returns a cached thumbnail immediately, or `nil` while kicking off an
    /// asynchronous load. The per-key revision map is `@Observable`-tracked,
    /// so the calling view will re-render once the thumbnail becomes available.
    func thumbnail(for storedFilePath: String, libraryURL: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(storedFilePath: storedFilePath, size: size)

        if let entry = backingCache.object(forKey: key as NSString) {
            return entry.image
        }

        loadThumbnailAsync(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size, key: key)
        return nil
    }

    func isObserved(storedFilePath: String, size: CGSize) -> Bool {
        let key = cacheKey(storedFilePath: storedFilePath, size: size)
        _ = readyThumbnailRevisions[key]
        return backingCache.object(forKey: key as NSString) != nil || inFlightTasks[key] != nil
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
                let estimatedCost = Int(size.width * size.height * 4)
                let entry = ThumbnailEntry(key: key, image: cachedImage)
                self.backingCache.setObject(entry, forKey: key as NSString, cost: estimatedCost)
                self.readyThumbnailRevisions[key, default: 0] += 1
            }
        }
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? ThumbnailEntry else { return }
        Task { @MainActor [weak self] in
            self?.readyThumbnailRevisions.removeValue(forKey: entry.key)
        }
    }

    private func cacheKey(storedFilePath: String, size: CGSize) -> String {
        "\(storedFilePath)_\(Int(size.width))x\(Int(size.height))"
    }
}
