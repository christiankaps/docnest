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
        source.resume()

        // Initial scan to catch files added while the app was closed
        scanFolderAsync(entry)

        Self.logger.info("Started monitoring: \(path, privacy: .public)")
    }

    func stopMonitoring(id: UUID) {
        guard let existing = monitors.removeValue(forKey: id) else { return }
        knownSnapshotsByFolderID.removeValue(forKey: id)
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

        Task.detached(priority: .utility) {
            let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return }

            let snapshots: [FileSnapshot] = contents.compactMap { url in
                guard url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
                    return nil
                }

                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else {
                    return nil
                }

                return FileSnapshot(
                    path: url.path,
                    modificationDate: values?.contentModificationDate ?? .distantPast
                )
            }

            await MainActor.run {
                guard let monitor = self.monitors[folderID] else { return }

                let previousSnapshots = self.knownSnapshotsByFolderID[folderID] ?? [:]
                let result = Self.newPDFURLs(
                    from: snapshots,
                    previousSnapshots: previousSnapshots
                )
                self.knownSnapshotsByFolderID[folderID] = result.updatedSnapshots

                guard !result.urls.isEmpty else { return }

                Self.logger.info("Found \(result.urls.count) new or updated PDF(s) in \(folderPath, privacy: .public)")
                self.onNewPDFsDetected?(result.urls, monitor.labelIDs)
            }
        }
    }
}
