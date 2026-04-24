import AppKit
import PDFKit

@MainActor
@Observable
final class ThumbnailCache: NSObject, NSCacheDelegate {
    enum PreviewThumbnailResult {
        case exact(NSImage)
        case fallback(NSImage)
        case unavailable
    }

    private final class ThumbnailEntry: NSObject {
        let key: String
        let image: NSImage

        init(key: String, image: NSImage) {
            self.key = key
            self.image = image
        }
    }

    private(set) var readyThumbnailRevisions: [String: Int] = [:]
    private(set) var loadCompletionRevisions: [String: Int] = [:]
    private let backingCache = NSCache<NSString, ThumbnailEntry>()
    private var inFlightTasks: [String: Task<Void, Never>] = [:]
    private var failedLoadDates: [String: Date] = [:]
    private let countLimit: Int
    private let failedLoadRetryInterval: TimeInterval = 1

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
        let key = cacheKey(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size)

        if let entry = backingCache.object(forKey: key as NSString) {
            return entry.image
        }

        if canRetryLoad(for: key) {
            loadThumbnailAsync(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size, key: key)
        }
        return nil
    }

    /// Returns the best cached thumbnail currently available for preview UI.
    ///
    /// The inspector prefers the exact requested size, but it can temporarily
    /// reuse a thumbnail cached at a nearby size so a preview appears
    /// immediately while a sharper version loads in the background.
    func previewThumbnailResult(
        for storedFilePath: String,
        libraryURL: URL,
        preferredSize: CGSize
    ) -> PreviewThumbnailResult {
        let preferredKey = cacheKey(
            storedFilePath: storedFilePath,
            libraryURL: libraryURL,
            size: preferredSize
        )
        _ = loadCompletionRevisions[preferredKey]

        if let entry = backingCache.object(forKey: preferredKey as NSString) {
            return .exact(entry.image)
        }

        if canRetryLoad(for: preferredKey) {
            loadThumbnailAsync(
                storedFilePath: storedFilePath,
                libraryURL: libraryURL,
                size: preferredSize,
                key: preferredKey
            )
        }

        let fallbackKeys = Self.bestAvailableKeys(
            for: storedFilePath,
            libraryURL: libraryURL,
            availableKeys: Array(readyThumbnailRevisions.keys),
            preferredSize: preferredSize
        )

        for fallbackKey in fallbackKeys {
            if let image = backingCache.object(forKey: fallbackKey as NSString)?.image {
                return .fallback(image)
            }
        }

        return .unavailable
    }

    func isObserved(storedFilePath: String, libraryURL: URL, size: CGSize) -> Bool {
        let key = cacheKey(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size)
        _ = readyThumbnailRevisions[key]
        _ = loadCompletionRevisions[key]
        return backingCache.object(forKey: key as NSString) != nil || inFlightTasks[key] != nil
    }

    /// Returns whether the preferred preview thumbnail is still loading.
    func isPreviewThumbnailLoading(for storedFilePath: String, libraryURL: URL, preferredSize: CGSize) -> Bool {
        let key = cacheKey(
            storedFilePath: storedFilePath,
            libraryURL: libraryURL,
            size: preferredSize
        )
        _ = loadCompletionRevisions[key]
        return inFlightTasks[key] != nil
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
            var didCacheThumbnail = false
            var wasCancelled = false
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.inFlightTasks.removeValue(forKey: key)
                    if wasCancelled || didCacheThumbnail {
                        self.failedLoadDates.removeValue(forKey: key)
                    } else {
                        self.failedLoadDates[key] = .now
                    }
                    self.loadCompletionRevisions[key, default: 0] += 1
                }
            }

            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }
            guard DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL) else { return }
            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }
            guard let pdfDocument = PDFDocument(url: fileURL),
                  let page = pdfDocument.page(at: 0) else { return }

            let nsImage = page.thumbnail(of: NSSize(width: size.width, height: size.height), for: .mediaBox)
            guard let imageData = nsImage.tiffRepresentation else { return }
            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let cachedImage = NSImage(data: imageData) else { return }
                let estimatedCost = Int(size.width * size.height * 4)
                let entry = ThumbnailEntry(key: key, image: cachedImage)
                self.backingCache.setObject(entry, forKey: key as NSString, cost: estimatedCost)
                self.readyThumbnailRevisions[key, default: 0] += 1
                didCacheThumbnail = true
            }
        }
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? ThumbnailEntry else { return }
        Task { @MainActor [weak self] in
            self?.readyThumbnailRevisions.removeValue(forKey: entry.key)
        }
    }

    /// Chooses the closest cached thumbnail size for a given document path.
    ///
    /// The helper ignores thumbnails for other documents and prefers the cached
    /// size whose pixel area is closest to the requested preview area.
    nonisolated static func bestAvailableKeys(
        for storedFilePath: String,
        libraryURL: URL,
        availableKeys: [String],
        preferredSize: CGSize
    ) -> [String] {
        let prefix = "\(cacheIdentity(storedFilePath: storedFilePath, libraryURL: libraryURL))_"
        let preferredArea = max(preferredSize.width * preferredSize.height, 1)

        return availableKeys
            .compactMap { key -> (key: String, areaDelta: CGFloat, area: CGFloat)? in
                guard key.hasPrefix(prefix),
                      let size = cachedSize(from: key) else {
                    return nil
                }

                let area = size.width * size.height
                return (key, abs(area - preferredArea), area)
            }
            .sorted { lhs, rhs in
                if lhs.areaDelta == rhs.areaDelta {
                    return lhs.area > rhs.area
                }
                return lhs.areaDelta < rhs.areaDelta
            }
            .map(\.key)
    }

    private func cacheKey(storedFilePath: String, libraryURL: URL, size: CGSize) -> String {
        "\(Self.cacheIdentity(storedFilePath: storedFilePath, libraryURL: libraryURL))_\(Int(size.width))x\(Int(size.height))"
    }

    private nonisolated static func cacheIdentity(storedFilePath: String, libraryURL: URL) -> String {
        let libraryPath = libraryURL.standardizedFileURL.path
        let identity = "\(libraryPath)\n\(storedFilePath)"
        return Data(identity.utf8).base64EncodedString()
    }

    private nonisolated static func cachedSize(from key: String) -> CGSize? {
        guard let separatorIndex = key.lastIndex(of: "_") else { return nil }
        let suffix = key[key.index(after: separatorIndex)...]
        let components = suffix.split(separator: "x", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]) else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func canRetryLoad(for key: String) -> Bool {
        guard let failedAt = failedLoadDates[key] else { return true }
        return Date.now.timeIntervalSince(failedAt) >= failedLoadRetryInterval
    }
}
