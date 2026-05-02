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

    private struct ThumbnailRequest {
        let storedFilePath: String
        let libraryURL: URL
        let size: CGSize
        let key: String
    }

    private(set) var readyThumbnailRevisions: [String: Int] = [:]
    private(set) var loadCompletionRevisions: [String: Int] = [:]
    @ObservationIgnored private let backingCache = NSCache<NSString, ThumbnailEntry>()
    @ObservationIgnored private var inFlightTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingThumbnailRequests: [String: ThumbnailRequest] = [:]
    @ObservationIgnored private var pendingThumbnailRequestKeys: [String] = []
    @ObservationIgnored private var failedLoadDates: [String: Date] = [:]
    @ObservationIgnored private var metadataAccessDates: [String: Date] = [:]
    private let countLimit: Int
    private let metadataCountLimit: Int
    private let inFlightLimit: Int
    private let failedLoadRetryInterval: TimeInterval
    @ObservationIgnored private var pendingRetryTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRetryDate: Date?
    @ObservationIgnored private var pendingRenderStatePruneTask: Task<Void, Never>?

    init(countLimit: Int = 500, inFlightLimit: Int = 8, failedLoadRetryInterval: TimeInterval = 1) {
        self.countLimit = max(countLimit, 1)
        self.metadataCountLimit = max(countLimit * 2, countLimit + 50, 1)
        self.inFlightLimit = max(inFlightLimit, 1)
        self.failedLoadRetryInterval = max(failedLoadRetryInterval, 0)
        super.init()
        backingCache.countLimit = self.countLimit
        backingCache.totalCostLimit = self.countLimit * 512 * 1024
        backingCache.delegate = self
    }

    deinit {
        backingCache.delegate = nil
        for task in inFlightTasks.values {
            task.cancel()
        }
        pendingRetryTask?.cancel()
        pendingRenderStatePruneTask?.cancel()
    }

    /// Returns a cached thumbnail immediately, or `nil` while kicking off an
    /// asynchronous load. The per-key revision map is `@Observable`-tracked,
    /// so the calling view will re-render once the thumbnail becomes available.
    func thumbnail(for storedFilePath: String, libraryURL: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size)
        markTrackedKey(key)

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
        markTrackedKey(preferredKey)
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
        markTrackedKey(key)
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
        markTrackedKey(key)
        _ = loadCompletionRevisions[key]
        return inFlightTasks[key] != nil
    }

    func cancelAllInFlightTasks() {
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
        pendingThumbnailRequests.removeAll()
        pendingThumbnailRequestKeys.removeAll()
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        pendingRetryDate = nil
        pendingRenderStatePruneTask?.cancel()
        pendingRenderStatePruneTask = nil
    }

    private func loadThumbnailAsync(storedFilePath: String, libraryURL: URL, size: CGSize, key: String) {
        guard inFlightTasks[key] == nil else { return }
        markTrackedKey(key)

        let request = ThumbnailRequest(
            storedFilePath: storedFilePath,
            libraryURL: libraryURL,
            size: size,
            key: key
        )
        guard inFlightTasks.count < inFlightLimit else {
            enqueueThumbnailRequest(request)
            return
        }

        pendingThumbnailRequests.removeValue(forKey: key)
        pendingThumbnailRequestKeys.removeAll { $0 == key }
        startThumbnailLoad(request)
    }

    private func enqueueThumbnailRequest(_ request: ThumbnailRequest) {
        if pendingThumbnailRequests[request.key] == nil {
            pendingThumbnailRequestKeys.append(request.key)
        }
        pendingThumbnailRequests[request.key] = request
        markTrackedKey(request.key)
    }

    private func startPendingThumbnailLoads() {
        var inspectedCount = 0
        let initialPendingCount = pendingThumbnailRequestKeys.count
        while inFlightTasks.count < inFlightLimit,
              inspectedCount < initialPendingCount,
              !pendingThumbnailRequestKeys.isEmpty {
            let key = pendingThumbnailRequestKeys.removeFirst()
            inspectedCount += 1
            guard let request = pendingThumbnailRequests[key] else {
                continue
            }
            guard backingCache.object(forKey: key as NSString) == nil else {
                pendingThumbnailRequests.removeValue(forKey: key)
                continue
            }
            guard canRetryLoad(for: key) else {
                pendingThumbnailRequestKeys.append(key)
                schedulePendingRetry(for: key)
                continue
            }
            pendingThumbnailRequests.removeValue(forKey: key)
            startThumbnailLoad(request)
        }
    }

    private func startThumbnailLoad(_ request: ThumbnailRequest) {
        let key = request.key
        let fileURL = DocumentStorageService.fileURL(
            for: request.storedFilePath,
            libraryURL: request.libraryURL
        )

        #if DEBUG
        let thumbnailLoadDidStartForTesting = thumbnailLoadDidStartForTesting
        #endif

        inFlightTasks[key] = Task.detached(priority: .utility) { [weak self] in
            var didCacheThumbnail = false
            var wasCancelled = false
            defer {
                let completedWithCachedThumbnail = didCacheThumbnail
                let completedWithCancellation = wasCancelled
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.inFlightTasks.removeValue(forKey: key)
                    if completedWithCancellation || completedWithCachedThumbnail {
                        self.failedLoadDates.removeValue(forKey: key)
                    } else {
                        self.failedLoadDates[key] = .now
                    }
                    self.loadCompletionRevisions[key, default: 0] += 1
                    self.markTrackedKey(key, pruneRenderState: true)
                    self.startPendingThumbnailLoads()
                }
            }

            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }
            #if DEBUG
            thumbnailLoadDidStartForTesting?()
            #endif

            guard DocumentStorageService.fileExists(
                at: request.storedFilePath,
                libraryURL: request.libraryURL
            ) else { return }
            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }
            guard let pdfDocument = PDFDocument(url: fileURL),
                  let page = pdfDocument.page(at: 0) else { return }

            let nsImage = page.thumbnail(
                of: NSSize(width: request.size.width, height: request.size.height),
                for: .mediaBox
            )
            guard let imageData = nsImage.tiffRepresentation else { return }
            guard !Task.isCancelled else {
                wasCancelled = true
                return
            }

            didCacheThumbnail = await MainActor.run { [weak self] in
                guard let self else { return false }
                guard let cachedImage = NSImage(data: imageData) else { return false }
                let estimatedCost = Int(request.size.width * request.size.height * 4)
                let entry = ThumbnailEntry(key: key, image: cachedImage)
                self.backingCache.setObject(entry, forKey: key as NSString, cost: estimatedCost)
                self.readyThumbnailRevisions[key, default: 0] += 1
                self.markTrackedKey(key, pruneRenderState: true)
                return true
            }
        }
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? ThumbnailEntry else { return }
        Task { @MainActor [weak self] in
            self?.removeTrackedMetadata(for: entry.key)
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

    private func retryDelay(for key: String) -> TimeInterval? {
        guard let failedAt = failedLoadDates[key] else { return nil }
        let retryAt = failedAt.addingTimeInterval(failedLoadRetryInterval)
        return max(retryAt.timeIntervalSinceNow, 0)
    }

    private func schedulePendingRetry(for key: String) {
        guard let retryDelay = retryDelay(for: key) else { return }
        let retryDate = Date().addingTimeInterval(retryDelay)
        if let pendingRetryDate, pendingRetryDate <= retryDate {
            return
        }

        pendingRetryTask?.cancel()
        pendingRetryDate = retryDate
        pendingRetryTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(retryDelay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.pendingRetryTask = nil
            self.pendingRetryDate = nil
            self.startPendingThumbnailLoads()
        }
    }

    private func markTrackedKey(_ key: String, pruneRenderState: Bool = false) {
        metadataAccessDates[key] = .now
        if pruneRenderState {
            pruneTrackedMetadataIfNeeded(pruneRenderState: true)
        } else {
            scheduleRenderStatePruneIfNeeded()
        }
    }

    private func scheduleRenderStatePruneIfNeeded() {
        guard metadataAccessDates.count > metadataCountLimit ||
              loadCompletionRevisions.count > metadataCountLimit else {
            return
        }
        guard pendingRenderStatePruneTask == nil else { return }

        pendingRenderStatePruneTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.pendingRenderStatePruneTask = nil
            self.pruneTrackedMetadataIfNeeded(pruneRenderState: true)
        }
    }

    private func pruneTrackedMetadataIfNeeded(pruneRenderState: Bool) {
        guard metadataAccessDates.count > metadataCountLimit else { return }

        var protectedKeys = Set(inFlightTasks.keys)
            .union(pendingThumbnailRequests.keys)
        if pruneRenderState {
            protectedKeys.formUnion(readyThumbnailRevisions.keys)
        }
        let removableKeys = metadataAccessDates
            .filter { key, _ in !protectedKeys.contains(key) }
            .sorted { lhs, rhs in lhs.value < rhs.value }
            .map(\.key)

        for key in removableKeys where metadataAccessDates.count > metadataCountLimit {
            removeTrackedMetadata(for: key, removeRenderRevisions: pruneRenderState)
        }
    }

    private func removeTrackedMetadata(for key: String, removeRenderRevisions: Bool = true) {
        if removeRenderRevisions {
            readyThumbnailRevisions.removeValue(forKey: key)
            loadCompletionRevisions.removeValue(forKey: key)
        }
        failedLoadDates.removeValue(forKey: key)
        metadataAccessDates.removeValue(forKey: key)
        pendingThumbnailRequests.removeValue(forKey: key)
        pendingThumbnailRequestKeys.removeAll { $0 == key }
        if pendingThumbnailRequests.isEmpty {
            pendingRetryTask?.cancel()
            pendingRetryTask = nil
            pendingRetryDate = nil
        }
    }

    #if DEBUG
    var thumbnailLoadDidStartForTesting: (() -> Void)?

    func registerTrackedKeyForTesting(_ key: String) {
        loadCompletionRevisions[key, default: 0] += 1
        failedLoadDates[key] = .now
        markTrackedKey(key, pruneRenderState: true)
    }

    func registerUnprunedCompletedLoadForTesting(_ key: String) {
        loadCompletionRevisions[key, default: 0] += 1
        failedLoadDates[key] = .now
        metadataAccessDates[key] = .now
    }

    var trackedMetadataCountForTesting: Int {
        metadataAccessDates.count
    }

    var pendingThumbnailRequestCountForTesting: Int {
        pendingThumbnailRequests.count
    }

    var inFlightTaskCountForTesting: Int {
        inFlightTasks.count
    }

    func enqueueBackedOffThumbnailRequestForTesting(
        storedFilePath: String,
        libraryURL: URL,
        size: CGSize
    ) {
        let key = cacheKey(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size)
        failedLoadDates[key] = .now
        enqueueThumbnailRequest(
            ThumbnailRequest(
                storedFilePath: storedFilePath,
                libraryURL: libraryURL,
                size: size,
                key: key
            )
        )
    }

    func startPendingThumbnailLoadsForTesting() {
        startPendingThumbnailLoads()
    }

    func cacheThumbnailForTesting(
        storedFilePath: String,
        libraryURL: URL,
        size: CGSize,
        image: NSImage
    ) {
        let key = cacheKey(storedFilePath: storedFilePath, libraryURL: libraryURL, size: size)
        let estimatedCost = Int(size.width * size.height * 4)
        backingCache.setObject(
            ThumbnailEntry(key: key, image: image),
            forKey: key as NSString,
            cost: estimatedCost
        )
        readyThumbnailRevisions[key, default: 0] += 1
        markTrackedKey(key)
    }
    #endif
}
