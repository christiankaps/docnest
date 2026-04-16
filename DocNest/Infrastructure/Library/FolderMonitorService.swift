import Foundation
import CoreServices
import OSLog

@MainActor
/// Watches configured filesystem folders for new or changed PDFs.
///
/// The monitor combines recursive full scans with event-driven incremental
/// updates. Discovered files are handed back to higher-level code, which then
/// routes them through the normal import pipeline.
final class FolderMonitorService {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "FolderMonitor")

    private struct MonitoredFolder {
        let watchFolderID: UUID
        let monitorToken: Int
        let folderPath: String
        var labelIDs: [UUID]
        let eventStream: FSEventStreamRef
        let callbackContext: UnsafeMutableRawPointer
    }

    private struct FileEvent {
        let path: String
        let flags: FSEventStreamEventFlags
    }

    private final class EventStreamContext {
        weak var service: FolderMonitorService?
        let folderID: UUID
        let monitorToken: Int

        init(service: FolderMonitorService, folderID: UUID, monitorToken: Int) {
            self.service = service
            self.folderID = folderID
            self.monitorToken = monitorToken
        }
    }

    struct FileSnapshot: Equatable {
        let path: String
        let modificationDate: Date
    }

    private var monitors: [UUID: MonitoredFolder] = [:]
    private var knownSnapshotsByFolderID: [UUID: [String: Date]] = [:]
    private var monitorTokenByFolderID: [UUID: Int] = [:]
    private var scanGenerationByFolderID: [UUID: Int] = [:]
    private var lastCompletedScanAtByFolderID: [UUID: Date] = [:]
    private var lastCompletedRecoveryScanAtByFolderID: [UUID: Date] = [:]
    private var pendingScanTasks: [UUID: Task<Void, Never>] = [:]
    private var activeScanTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFullScanIDs: Set<UUID> = []
    private var pendingEventFlagsByFolderID: [UUID: [String: FSEventStreamEventFlags]] = [:]
    private let minimumScanInterval: TimeInterval = 1
    private let minimumRecoveryScanInterval: TimeInterval = 5
    private let monitorQueue = DispatchQueue(
        label: "com.kaps.docnest.foldermonitor",
        qos: .utility
    )

    var onNewPDFsDetected: ((_ urls: [URL], _ labelIDs: [UUID]) -> Void)?

    // MARK: - Public API

    /// Starts monitoring one watch folder, replacing any existing monitor for
    /// the same watch-folder identifier.
    func startMonitoring(_ watchFolder: WatchFolder) {
        stopMonitoring(id: watchFolder.id)

        let path = watchFolder.folderPath
        guard folderExists(at: path) else {
            Self.logger.warning("Watch folder path does not exist: \(path, privacy: .public)")
            return
        }

        let monitorToken = (monitorTokenByFolderID[watchFolder.id] ?? 0) &+ 1
        monitorTokenByFolderID[watchFolder.id] = monitorToken
        let callbackContext = Unmanaged.passRetained(
            EventStreamContext(service: self, folderID: watchFolder.id, monitorToken: monitorToken)
        ).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: callbackContext,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            Self.handleFileSystemEvents,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            Unmanaged<EventStreamContext>.fromOpaque(callbackContext).release()
            Self.logger.error("Failed to create event stream for: \(path, privacy: .public)")
            return
        }
        FSEventStreamSetDispatchQueue(stream, monitorQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<EventStreamContext>.fromOpaque(callbackContext).release()
            Self.logger.error("Failed to start event stream for: \(path, privacy: .public)")
            return
        }

        let entry = MonitoredFolder(
            watchFolderID: watchFolder.id,
            monitorToken: monitorToken,
            folderPath: path,
            labelIDs: watchFolder.labelIDs,
            eventStream: stream,
            callbackContext: callbackContext
        )

        monitors[watchFolder.id] = entry
        scanGenerationByFolderID[watchFolder.id] = (scanGenerationByFolderID[watchFolder.id] ?? 0) &+ 1

        // Initial scan to catch files added while the app was closed
        pendingFullScanIDs.insert(watchFolder.id)
        scheduleScan(for: entry)

        Self.logger.info("Started monitoring: \(path, privacy: .public)")
    }

    func stopMonitoring(id: UUID) {
        guard let existing = monitors.removeValue(forKey: id) else { return }
        pendingScanTasks[id]?.cancel()
        activeScanTasks[id]?.cancel()
        pendingScanTasks.removeValue(forKey: id)
        activeScanTasks.removeValue(forKey: id)
        pendingFullScanIDs.remove(id)
        pendingEventFlagsByFolderID.removeValue(forKey: id)
        knownSnapshotsByFolderID.removeValue(forKey: id)
        monitorTokenByFolderID[id] = (monitorTokenByFolderID[id] ?? 0) &+ 1
        scanGenerationByFolderID[id] = (scanGenerationByFolderID[id] ?? 0) &+ 1
        lastCompletedScanAtByFolderID.removeValue(forKey: id)
        lastCompletedRecoveryScanAtByFolderID.removeValue(forKey: id)
        FSEventStreamStop(existing.eventStream)
        FSEventStreamInvalidate(existing.eventStream)
        FSEventStreamRelease(existing.eventStream)
        Unmanaged<EventStreamContext>.fromOpaque(existing.callbackContext).release()
        Self.logger.info("Stopped monitoring: \(existing.folderPath, privacy: .public)")
    }

    func stopAll() {
        let ids = Array(monitors.keys)
        for id in ids {
            stopMonitoring(id: id)
        }
    }

    func updateLabelIDs(for id: UUID, labelIDs: [UUID]) {
        monitors[id]?.labelIDs = labelIDs
    }

    func isMonitoring(id: UUID) -> Bool {
        monitors[id] != nil
    }

    func monitoredFolderPath(for id: UUID) -> String? {
        monitors[id]?.folderPath
    }

    var monitoredIDs: Set<UUID> {
        Set(monitors.keys)
    }

    // MARK: - Status

    func folderExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Scanning

    /// Computes the delta between the latest recursive file snapshots and the
    /// previously known state for a watch folder.
    nonisolated static func newPDFURLs(
        from snapshots: [FileSnapshot],
        previousSnapshots: [String: Date]
    ) -> (urls: [URL], updatedSnapshots: [String: Date]) {
        let updatedSnapshots = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.path, $0.modificationDate) }
        )

        let urls = snapshots.compactMap { snapshot -> URL? in
            guard previousSnapshots[snapshot.path] != snapshot.modificationDate else {
                return nil
            }
            return URL(fileURLWithPath: snapshot.path)
        }

        return (urls, updatedSnapshots)
    }

    private static let handleFileSystemEvents: FSEventStreamCallback = { _, info, eventCount, eventPathsPointer, eventFlagsPointer, _ in
        guard let info else { return }
        let context = Unmanaged<EventStreamContext>.fromOpaque(info).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(eventPathsPointer)
            .takeUnretainedValue() as? [String] ?? []
        let flags = Array(UnsafeBufferPointer(start: eventFlagsPointer, count: eventCount))
        let events = zip(paths, flags).map { FileEvent(path: $0.0, flags: $0.1) }

        Task { @MainActor [weak service = context.service] in
            service?.enqueue(events: events, for: context.folderID, monitorToken: context.monitorToken)
        }
    }

    private func enqueue(events: [FileEvent], for folderID: UUID, monitorToken: Int) {
        guard monitorTokenByFolderID[folderID] == monitorToken else { return }
        guard let monitor = monitors[folderID] else { return }
        guard monitor.monitorToken == monitorToken else { return }

        for event in events {
            if Self.shouldPerformFullScan(for: event, in: monitor.folderPath) {
                pendingFullScanIDs.insert(folderID)
                continue
            }

            guard Self.shouldTrack(eventPath: event.path, in: monitor.folderPath) else { continue }
            pendingEventFlagsByFolderID[folderID, default: [:]][event.path, default: 0] |= event.flags
        }

        if pendingFullScanIDs.contains(folderID) || pendingEventFlagsByFolderID[folderID] != nil {
            scheduleScan(for: monitor)
        }
    }

    private func scheduleScan(for entry: MonitoredFolder) {
        let folderID = entry.watchFolderID
        let folderPath = entry.folderPath
        let scanGeneration = scanGenerationByFolderID[folderID] ?? 0

        if activeScanTasks[folderID] != nil {
            return
        }

        pendingScanTasks[folderID]?.cancel()
        let now = Date()
        let earliestIncrementalScanDate = lastCompletedScanAtByFolderID[folderID]
            .map { $0.addingTimeInterval(minimumScanInterval) } ?? now
        let earliestRecoveryScanDate = lastCompletedRecoveryScanAtByFolderID[folderID]
            .map { $0.addingTimeInterval(minimumRecoveryScanInterval) } ?? now
        let earliestScanDate = pendingFullScanIDs.contains(folderID)
            ? max(earliestIncrementalScanDate, earliestRecoveryScanDate)
            : earliestIncrementalScanDate
        let delayMilliseconds = max(250, Int(ceil(earliestScanDate.timeIntervalSince(now) * 1_000)))
        pendingScanTasks[folderID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            guard self.scanGenerationByFolderID[folderID] == scanGeneration else { return }

            self.pendingScanTasks[folderID] = nil
            let previousSnapshots = self.knownSnapshotsByFolderID[folderID] ?? [:]
            let shouldPerformFullScan = self.pendingFullScanIDs.remove(folderID) != nil
            let pendingEvents = self.pendingEventFlagsByFolderID.removeValue(forKey: folderID) ?? [:]
            let scanTask = Task.detached(priority: .utility) {
                let result = if shouldPerformFullScan {
                    Self.scanSnapshots(in: folderPath, previousSnapshots: previousSnapshots)
                } else {
                    Self.applyFileEvents(
                        pendingEvents,
                        in: folderPath,
                        previousSnapshots: previousSnapshots
                    )
                }
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.scanGenerationByFolderID[folderID] == scanGeneration else { return }
                    guard let monitor = self.monitors[folderID] else { return }
                    self.activeScanTasks[folderID] = nil

                    self.knownSnapshotsByFolderID[folderID] = result.updatedSnapshots
                    self.lastCompletedScanAtByFolderID[folderID] = Date()
                    if shouldPerformFullScan {
                        self.lastCompletedRecoveryScanAtByFolderID[folderID] = Date()
                    }

                    if !result.urls.isEmpty {
                        Self.logger.info("Found \(result.urls.count) new or updated PDF(s) in \(folderPath, privacy: .public)")
                        self.onNewPDFsDetected?(result.urls, monitor.labelIDs)
                    }

                    if (self.pendingFullScanIDs.contains(folderID)
                        || self.pendingEventFlagsByFolderID[folderID] != nil),
                       let followUpMonitor = self.monitors[folderID] {
                        self.scheduleScan(for: followUpMonitor)
                    }
                }
            }

            self.activeScanTasks[folderID] = scanTask
        }
    }

    nonisolated private static func shouldPerformFullScan(for event: FileEvent, in folderPath: String) -> Bool {
        let fullRescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount
                | kFSEventStreamEventFlagUnmount
        )
        let directoryFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemIsDir
                | kFSEventStreamEventFlagItemRenamed
                | kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
        )
        return event.path == folderPath
            || (event.flags & fullRescanFlags) != 0
            || (isDescendantPath(event.path, of: folderPath) && (event.flags & directoryFlags) != 0)
    }

    nonisolated private static func shouldTrack(eventPath: String, in folderPath: String) -> Bool {
        isDescendantPath(eventPath, of: folderPath)
    }

    nonisolated static func scanSnapshots(
        in folderPath: String,
        previousSnapshots: [String: Date]
    ) -> (urls: [URL], updatedSnapshots: [String: Date]) {
        let snapshots = recursivePDFSnapshots(in: folderPath)
        return newPDFURLs(from: snapshots, previousSnapshots: previousSnapshots)
    }

    nonisolated static func applyFileEvents(
        _ eventFlagsByPath: [String: FSEventStreamEventFlags],
        in folderPath: String,
        previousSnapshots: [String: Date]
    ) -> (urls: [URL], updatedSnapshots: [String: Date]) {
        guard !eventFlagsByPath.isEmpty else {
            return ([], previousSnapshots)
        }

        var updatedSnapshots = previousSnapshots
        var urls: [URL] = []
        urls.reserveCapacity(eventFlagsByPath.count)

        for (path, flags) in eventFlagsByPath {
            guard isDescendantPath(path, of: folderPath) else { continue }

            let removedFlags = FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemRemoved
                    | kFSEventStreamEventFlagItemIsDir
            )
            if flags & removedFlags != 0 {
                removeSnapshots(atOrBelow: path, from: &updatedSnapshots)
                continue
            }

            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
                removeSnapshots(atOrBelow: path, from: &updatedSnapshots)
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else {
                removeSnapshots(atOrBelow: path, from: &updatedSnapshots)
                continue
            }

            let modificationDate = values?.contentModificationDate ?? .distantPast
            if previousSnapshots[path] != modificationDate {
                urls.append(url)
            }
            updatedSnapshots[path] = modificationDate
        }

        return (urls, updatedSnapshots)
    }

    nonisolated private static func recursivePDFSnapshots(in folderPath: String) -> [FileSnapshot] {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let urls = ImportPDFDocumentsUseCase.enumeratePDFs(in: folderURL)
        var snapshots: [FileSnapshot] = []
        snapshots.reserveCapacity(urls.count)

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            snapshots.append(
                FileSnapshot(
                    path: url.path,
                    modificationDate: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        return snapshots
    }

    nonisolated private static func isDescendantPath(_ path: String, of folderPath: String) -> Bool {
        let standardizedFolder = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = standardizedFolder.hasSuffix("/") ? standardizedFolder : standardizedFolder + "/"
        return standardizedPath == standardizedFolder
            || standardizedPath.hasPrefix(prefix)
    }

    nonisolated private static func removeSnapshots(atOrBelow path: String, from snapshots: inout [String: Date]) {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = standardizedPath + "/"
        for key in Array(snapshots.keys) where key == standardizedPath || key.hasPrefix(prefix) {
            snapshots.removeValue(forKey: key)
        }
    }
}
