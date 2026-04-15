import Foundation
import OSLog

@MainActor
final class FolderMonitorService {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "FolderMonitor")

    private struct MonitoredFolder {
        let watchFolderID: UUID
        let folderPath: String
        var labelIDs: [UUID]
        let fileDescriptor: Int32
        let dispatchSource: DispatchSourceFileSystemObject
    }

    struct FileSnapshot: Equatable {
        let path: String
        let modificationDate: Date
    }

    private var monitors: [UUID: MonitoredFolder] = [:]
    private var knownSnapshotsByFolderID: [UUID: [String: Date]] = [:]
    private var scanGenerationByFolderID: [UUID: Int] = [:]
    private var lastCompletedScanAtByFolderID: [UUID: Date] = [:]
    private var pendingScanTasks: [UUID: Task<Void, Never>] = [:]
    private var activeScanTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingRescanIDs: Set<UUID> = []
    private let minimumScanInterval: TimeInterval = 1
    private let monitorQueue = DispatchQueue(
        label: "com.kaps.docnest.foldermonitor",
        qos: .utility
    )

    var onNewPDFsDetected: ((_ urls: [URL], _ labelIDs: [UUID]) -> Void)?

    // MARK: - Public API

    func startMonitoring(_ watchFolder: WatchFolder) {
        stopMonitoring(id: watchFolder.id)

        let path = watchFolder.folderPath
        guard folderExists(at: path) else {
            Self.logger.warning("Watch folder path does not exist: \(path, privacy: .public)")
            return
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Failed to open file descriptor for: \(path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: monitorQueue
        )

        let entry = MonitoredFolder(
            watchFolderID: watchFolder.id,
            folderPath: path,
            labelIDs: watchFolder.labelIDs,
            fileDescriptor: fd,
            dispatchSource: source
        )

        let folderID = watchFolder.id
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let monitor = self.monitors[folderID] else { return }
                self.scanFolderAsync(monitor)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        monitors[watchFolder.id] = entry
        scanGenerationByFolderID[watchFolder.id] = (scanGenerationByFolderID[watchFolder.id] ?? 0) &+ 1
        source.resume()

        // Initial scan to catch files added while the app was closed
        scanFolderAsync(entry)

        Self.logger.info("Started monitoring: \(path, privacy: .public)")
    }

    func stopMonitoring(id: UUID) {
        guard let existing = monitors.removeValue(forKey: id) else { return }
        pendingScanTasks[id]?.cancel()
        activeScanTasks[id]?.cancel()
        pendingScanTasks.removeValue(forKey: id)
        activeScanTasks.removeValue(forKey: id)
        pendingRescanIDs.remove(id)
        knownSnapshotsByFolderID.removeValue(forKey: id)
        scanGenerationByFolderID[id] = (scanGenerationByFolderID[id] ?? 0) &+ 1
        lastCompletedScanAtByFolderID.removeValue(forKey: id)
        existing.dispatchSource.cancel()
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

    private func scanFolderAsync(_ entry: MonitoredFolder) {
        let folderID = entry.watchFolderID
        let folderPath = entry.folderPath
        let scanGeneration = scanGenerationByFolderID[folderID] ?? 0

        if activeScanTasks[folderID] != nil {
            pendingRescanIDs.insert(folderID)
            return
        }

        pendingScanTasks[folderID]?.cancel()
        let now = Date()
        let earliestScanDate = lastCompletedScanAtByFolderID[folderID]
            .map { $0.addingTimeInterval(minimumScanInterval) } ?? now
        let delayMilliseconds = max(250, Int(ceil(earliestScanDate.timeIntervalSince(now) * 1_000)))
        pendingScanTasks[folderID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            guard self.scanGenerationByFolderID[folderID] == scanGeneration else { return }

            self.pendingScanTasks[folderID] = nil
            let previousSnapshots = self.knownSnapshotsByFolderID[folderID] ?? [:]
            let scanTask = Task.detached(priority: .utility) {
                let result = Self.scanSnapshots(in: folderPath, previousSnapshots: previousSnapshots)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.activeScanTasks[folderID] = nil
                    guard self.scanGenerationByFolderID[folderID] == scanGeneration else { return }
                    guard let monitor = self.monitors[folderID] else { return }

                    self.knownSnapshotsByFolderID[folderID] = result.updatedSnapshots
                    self.lastCompletedScanAtByFolderID[folderID] = Date()

                    if !result.urls.isEmpty {
                        Self.logger.info("Found \(result.urls.count) new or updated PDF(s) in \(folderPath, privacy: .public)")
                        self.onNewPDFsDetected?(result.urls, monitor.labelIDs)
                    }

                    if self.pendingRescanIDs.remove(folderID) != nil,
                       let followUpMonitor = self.monitors[folderID] {
                        self.scanFolderAsync(followUpMonitor)
                    }
                }
            }

            self.activeScanTasks[folderID] = scanTask
        }
    }

    nonisolated private static func scanSnapshots(
        in folderPath: String,
        previousSnapshots: [String: Date]
    ) -> (urls: [URL], updatedSnapshots: [String: Date]) {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return ([], [:])
        }

        let pdfURLs = contents.filter { url in
            url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        }

        var snapshots: [FileSnapshot] = []
        snapshots.reserveCapacity(pdfURLs.count)

        for url in pdfURLs {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else {
                continue
            }

            snapshots.append(
                FileSnapshot(
                    path: url.path,
                    modificationDate: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        return newPDFURLs(from: snapshots, previousSnapshots: previousSnapshots)
    }
}
