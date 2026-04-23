import AppKit
import SwiftUI
import SwiftData

// MARK: - About Window Controller

final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About DocNest"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class HelpWindowController: NSWindowController {
    static let shared = HelpWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DocNest Help"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 520)

        super.init(window: window)

        let hostingView = NSHostingView(rootView: HelpView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum AppSettingsPane: String, CaseIterable, Identifiable {
    case ocr
    case labels
    case watchFolders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocr: "OCR"
        case .labels: "Labels"
        case .watchFolders: "Watch Folders"
        }
    }

    var systemImage: String {
        switch self {
        case .ocr: "doc.text.viewfinder"
        case .labels: "tag"
        case .watchFolders: "folder.badge.gearshape"
        }
    }

    var shortDescription: String {
        switch self {
        case .ocr: "Text extraction backend"
        case .labels: "Tags, colors, and groups"
        case .watchFolders: "Automatic import locations"
        }
    }

    var subtitle: String {
        switch self {
        case .ocr:
            "Choose which OCR engine DocNest uses when extracting searchable text from PDFs."
        case .labels:
            "Organize label names, colors, icons, and groups for the current library."
        case .watchFolders:
            "Manage monitored Finder folders that automatically import PDFs."
        }
    }
}

@MainActor
final class AppSettingsController: ObservableObject {
    static let shared = AppSettingsController()

    @Published var selectedPane: AppSettingsPane = .labels
    @Published var modelContainer: ModelContainer?
    @Published var libraryCoordinator: LibraryCoordinator?

    private init() {}

    func show(_ pane: AppSettingsPane? = nil) {
        if let pane {
            selectedPane = pane
        }
        SettingsWindowController.shared.showWindow(nil)
    }

    func setActiveLibraryContext(coordinator: LibraryCoordinator, modelContainer: ModelContainer?) {
        libraryCoordinator = coordinator
        self.modelContainer = modelContainer
    }

    func clearActiveLibraryContext() {
        libraryCoordinator = nil
        modelContainer = nil
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 560)

        super.init(window: window)

        let hostingView = NSHostingView(rootView: AppSettingsRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - About View

struct AppReleaseVersion: Comparable, CustomStringConvertible {
    let year: Int
    let major: Int
    let minor: Int

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if trimmed.lowercased().hasPrefix("v") {
            normalized = String(trimmed.dropFirst())
        } else {
            normalized = trimmed
        }
        let parts = normalized.split(separator: ".")

        guard parts.count == 2 || parts.count == 3,
              let year = Int(parts[0]),
              let major = Int(parts[1]) else {
            return nil
        }

        let minor: Int
        if parts.count == 3 {
            guard let parsedMinor = Int(parts[2]) else { return nil }
            minor = parsedMinor
        } else {
            minor = 0
        }

        self.year = year
        self.major = major
        self.minor = minor
    }

    var description: String {
        minor == 0 ? "\(year).\(major)" : "\(year).\(major).\(minor)"
    }

    static func < (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }
}

struct AppUpdateInfo: Equatable {
    let currentVersion: AppReleaseVersion
    let latestVersion: AppReleaseVersion
    let releasePageURL: URL
    let downloadURL: URL
    let assetName: String?
}

private final class UpdateDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Int64, Int64?) async -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64?) async -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task {
            await onProgress(totalBytesWritten, expectedBytes)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case downloading(AppReleaseVersion)
        case installing(AppReleaseVersion)
        case upToDate(AppReleaseVersion)
        case updateAvailable(AppUpdateInfo)
        case failed(String)
    }

    struct UpdateProgress: Equatable {
        enum Phase: Equatable {
            case startingDownload
            case downloading(bytesReceived: Int64, totalBytes: Int64?)
            case mountingInstaller
            case stagingInstaller
            case verifyingInstaller
            case launchingInstaller
        }

        let version: AppReleaseVersion
        let phase: Phase

        var title: String {
            switch phase {
            case .startingDownload, .downloading:
                return "Downloading Version \(version)"
            case .mountingInstaller:
                return "Opening Installer"
            case .stagingInstaller:
                return "Staging Update"
            case .verifyingInstaller:
                return "Verifying Update"
            case .launchingInstaller:
                return "Launching Installer"
            }
        }

        var detail: String {
            switch phase {
            case .startingDownload:
                return "Preparing the download for version \(version)."
            case .downloading(let bytesReceived, let totalBytes):
                if let totalBytes, totalBytes > 0 {
                    return "\(Self.byteCountString(bytesReceived)) of \(Self.byteCountString(totalBytes)) downloaded."
                }
                if bytesReceived > 0 {
                    return "\(Self.byteCountString(bytesReceived)) downloaded."
                }
                return "Preparing the download for version \(version)."
            case .mountingInstaller:
                return "Step 2 of 5. Mounting the downloaded installer image."
            case .stagingInstaller:
                return "Step 3 of 5. Copying the new app into a temporary staging area."
            case .verifyingInstaller:
                return "Step 4 of 5. Checking the downloaded app before installation."
            case .launchingInstaller:
                return "Step 5 of 5. DocNest will relaunch automatically when the installer finishes."
            }
        }

        var fractionCompleted: Double? {
            guard case .downloading(let bytesReceived, let totalBytes) = phase,
                  let totalBytes,
                  totalBytes > 0 else {
                return nil
            }

            let fraction = Double(bytesReceived) / Double(totalBytes)
            return min(max(fraction, 0), 1)
        }

        var statusSummary: String {
            if let fractionCompleted {
                return "\(Int((fractionCompleted * 100).rounded()))%"
            }

            return "\(stepNumber)/\(totalSteps)"
        }

        private var stepNumber: Int {
            switch phase {
            case .startingDownload, .downloading:
                return 1
            case .mountingInstaller:
                return 2
            case .stagingInstaller:
                return 3
            case .verifyingInstaller:
                return 4
            case .launchingInstaller:
                return 5
            }
        }

        private var totalSteps: Int { 5 }

        private static let byteCountFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            formatter.includesUnit = true
            formatter.isAdaptive = true
            return formatter
        }()

        private static func byteCountString(_ byteCount: Int64) -> String {
            byteCountFormatter.string(fromByteCount: byteCount)
        }

        static func shouldAccept(_ incoming: Phase, over current: Phase?) -> Bool {
            guard let current else { return true }

            let incomingRank = phaseRank(for: incoming)
            let currentRank = phaseRank(for: current)
            guard incomingRank >= currentRank else { return false }

            if incomingRank > currentRank {
                return true
            }

            switch (current, incoming) {
            case (.downloading, .startingDownload):
                return false
            case let (.downloading(currentBytes, currentTotal), .downloading(incomingBytes, incomingTotal)):
                if incomingBytes > currentBytes {
                    return true
                }
                if incomingBytes == currentBytes, currentTotal == nil, incomingTotal != nil {
                    return true
                }
                return false
            default:
                return true
            }
        }

        private static func phaseRank(for phase: Phase) -> Int {
            switch phase {
            case .startingDownload, .downloading:
                return 0
            case .mountingInstaller:
                return 1
            case .stagingInstaller:
                return 2
            case .verifyingInstaller:
                return 3
            case .launchingInstaller:
                return 4
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var updateProgress: UpdateProgress?

    private let owner: String
    private let repo: String
    private var activeUpdateSessionID: UUID?

    init(owner: String = "christiankaps", repo: String = "docnest") {
        self.owner = owner
        self.repo = repo
    }

    func beginUpdateProgressSession(for version: AppReleaseVersion) -> UUID {
        let sessionID = UUID()
        activeUpdateSessionID = sessionID
        updateProgress = UpdateProgress(version: version, phase: .startingDownload)
        return sessionID
    }

    func clearUpdateProgressSession() {
        activeUpdateSessionID = nil
        updateProgress = nil
    }

    func applyUpdateProgress(
        _ phase: UpdateProgress.Phase,
        version: AppReleaseVersion,
        sessionID: UUID
    ) {
        guard activeUpdateSessionID == sessionID else { return }
        guard UpdateProgress.shouldAccept(phase, over: updateProgress?.phase) else { return }
        updateProgress = UpdateProgress(version: version, phase: phase)
    }

    func checkForUpdates(userInitiated: Bool = true) {
        guard !isBusy else { return }

        clearUpdateProgressSession()
        status = .checking

        Task {
            do {
                let info = try await fetchUpdateInfo()
                if let info {
                    clearUpdateProgressSession()
                    status = .updateAvailable(info)
                    if userInitiated {
                        presentUpdateAlert(info)
                    }
                } else if let currentVersion = currentInstalledVersion() {
                    clearUpdateProgressSession()
                    status = .upToDate(currentVersion)
                    if userInitiated {
                        presentInformationalAlert(
                            title: "DocNest Is Up to Date",
                            message: "You already have the latest released version installed."
                        )
                    }
                } else {
                    clearUpdateProgressSession()
                    status = .idle
                    if userInitiated {
                        presentInformationalAlert(
                            title: "Version Check Finished",
                            message: "No newer GitHub release was found."
                        )
                    }
                }
            } catch {
                clearUpdateProgressSession()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .failed(message)
                if userInitiated {
                    presentInformationalAlert(
                        title: "Update Check Failed",
                        message: message
                    )
                }
            }
        }
    }

    func installUpdate(_ info: AppUpdateInfo) {
        guard !isBusy else { return }

        let sessionID = beginInstallProgressSession(for: info.latestVersion)

        Task {
            do {
                let preparedInstaller = try await Self.prepareInstaller(
                    for: info,
                    currentAppURL: Bundle.main.bundleURL.standardizedFileURL,
                    currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                    progressHandler: { [weak self] phase in
                        await self?.applyUpdateProgress(phase, version: info.latestVersion, sessionID: sessionID)
                    }
                )
                status = .installing(info.latestVersion)
                applyUpdateProgress(.launchingInstaller, version: info.latestVersion, sessionID: sessionID)
                try Self.launchInstaller(preparedInstaller)
                NSApplication.shared.terminate(nil)
            } catch {
                clearUpdateProgressSession()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .failed(message)
                presentInformationalAlert(
                    title: "Update Installation Failed",
                    message: message
                )
            }
        }
    }

    @discardableResult
    func beginInstallProgressSession(for version: AppReleaseVersion) -> UUID {
        status = .downloading(version)
        return beginUpdateProgressSession(for: version)
    }

    private func fetchUpdateInfo() async throws -> AppUpdateInfo? {
        guard let currentVersion = currentInstalledVersion() else {
            throw UpdateError.invalidInstalledVersion
        }

        let response = try await fetchLatestRelease()
        guard let latestVersion = AppReleaseVersion(string: response.tagName) else {
            throw UpdateError.invalidRemoteVersion(response.tagName)
        }

        guard latestVersion > currentVersion else {
            return nil
        }

        let releasePageURL = URL(string: response.htmlURL) ?? releaseWebURL
        guard let dmgAsset = response.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw UpdateError.missingInstallerAsset
        }
        let downloadURL = URL(string: dmgAsset.browserDownloadURL) ?? releasePageURL

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL,
            assetName: dmgAsset.name
        )
    }

    private func fetchLatestRelease() async throws -> GitHubReleaseResponse {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DocNest", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw UpdateError.invalidPayload
        }
    }

    private func currentInstalledVersion() -> AppReleaseVersion? {
        let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return rawVersion.flatMap(AppReleaseVersion.init(string:))
    }

    private func presentUpdateAlert(_ info: AppUpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "A New Version of DocNest Is Available"
        alert.informativeText = "Installed: \(info.currentVersion)\nAvailable: \(info.latestVersion)"
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Release Page")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            installUpdate(info)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(info.releasePageURL)
        default:
            break
        }
    }

    private func presentInformationalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .failed:
            return false
        }
    }

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    private var releaseWebURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }

    private struct GitHubReleaseResponse: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct PreparedInstaller {
        let scriptURL: URL
    }

    private struct ProcessExecutionError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private enum UpdateError: LocalizedError {
        case invalidInstalledVersion
        case invalidRemoteVersion(String)
        case invalidResponse
        case httpStatus(Int)
        case invalidPayload
        case missingInstallerAsset
        case downloadMoveFailed
        case mountFailed(String)
        case detachFailed(String)
        case mountedVolumeNotFound
        case appBundleNotFound
        case invalidInstallerBundle(String)
        case signatureValidationFailed(String)
        case installerLaunchFailed
        case installerScriptWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion:
                return "The installed app version could not be read."
            case .invalidRemoteVersion(let version):
                return "The latest GitHub release version '\(version)' could not be understood."
            case .invalidResponse:
                return "GitHub returned an invalid response."
            case .httpStatus(let status):
                return "GitHub returned HTTP \(status)."
            case .invalidPayload:
                return "The latest release payload could not be decoded."
            case .missingInstallerAsset:
                return "The latest release does not include a DMG installer asset."
            case .downloadMoveFailed:
                return "The downloaded installer could not be staged."
            case .mountFailed(let message):
                return "The downloaded installer could not be mounted. \(message)"
            case .detachFailed(let message):
                return "The downloaded installer could not be unmounted. \(message)"
            case .mountedVolumeNotFound:
                return "The mounted installer volume could not be located."
            case .appBundleNotFound:
                return "The downloaded installer did not contain a DocNest app bundle."
            case .invalidInstallerBundle(let message):
                return message
            case .signatureValidationFailed(let message):
                return "The downloaded update could not be verified. \(message)"
            case .installerLaunchFailed:
                return "The update installer could not be launched."
            case .installerScriptWriteFailed:
                return "The update installer script could not be written."
            }
        }
    }

    nonisolated private static let diskImageDetachRetryDelay: TimeInterval = 0.2

    nonisolated private static func prepareInstaller(
        for info: AppUpdateInfo,
        currentAppURL: URL,
        currentProcessIdentifier: Int32,
        progressHandler: @escaping @Sendable (UpdateProgress.Phase) async -> Void
    ) async throws -> PreparedInstaller {
        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocNestUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)

        let installerFileName = info.assetName ?? "DocNest.dmg"
        let downloadedDMGURL = tempRootURL.appendingPathComponent(installerFileName)
        await progressHandler(.startingDownload)
        try await downloadInstaller(from: info.downloadURL, to: downloadedDMGURL, progressHandler: progressHandler)

        await progressHandler(.mountingInstaller)
        let mountedVolumeURL = try mountDiskImage(at: downloadedDMGURL)
        let stagedAppURL = tempRootURL.appendingPathComponent(currentAppURL.lastPathComponent, isDirectory: true)
        let expectedBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.kaps.docnest"
        let expectedTeamIdentifier = currentTeamIdentifier(for: currentAppURL)

        do {
            let mountedAppURL = try locateAppBundle(
                in: mountedVolumeURL,
                named: currentAppURL.lastPathComponent
            )
            await progressHandler(.stagingInstaller)
            try FileManager.default.copyItem(at: mountedAppURL, to: stagedAppURL)
            await progressHandler(.verifyingInstaller)
            try validateInstalledApp(
                at: stagedAppURL,
                expectedAppName: currentAppURL.lastPathComponent,
                expectedBundleIdentifier: expectedBundleIdentifier,
                expectedTeamIdentifier: expectedTeamIdentifier
            )
        } catch {
            try? detachDiskImage(at: mountedVolumeURL)
            throw error
        }

        // The installer only needs the staged app copy from here forward, so a lingering DMG is a cleanup issue.
        try? detachDiskImage(at: mountedVolumeURL)

        let scriptURL = tempRootURL.appendingPathComponent("install-update.sh")
        let script = installerScript(
            currentPID: currentProcessIdentifier,
            stagedAppURL: stagedAppURL,
            destinationAppURL: currentAppURL,
            temporaryRootURL: tempRootURL
        )

        guard FileManager.default.createFile(atPath: scriptURL.path, contents: script.data(using: .utf8)) else {
            throw UpdateError.installerScriptWriteFailed
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        return PreparedInstaller(scriptURL: scriptURL)
    }

    nonisolated private static func downloadInstaller(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (UpdateProgress.Phase) async -> Void
    ) async throws {
        var request = URLRequest(url: sourceURL)
        request.setValue("DocNest", forHTTPHeaderField: "User-Agent")
        let progressDelegate = UpdateDownloadProgressDelegate { bytesReceived, totalBytes in
            await progressHandler(.downloading(bytesReceived: bytesReceived, totalBytes: totalBytes))
        }
        let (temporaryURL, _) = try await URLSession.shared.download(for: request, delegate: progressDelegate)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw UpdateError.downloadMoveFailed
        }
    }

    nonisolated private static func mountDiskImage(at diskImageURL: URL) throws -> URL {
        try mountDiskImage(at: diskImageURL, processRunner: runProcess)
    }

    nonisolated static func mountDiskImage(
        at diskImageURL: URL,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data
    ) throws -> URL {
        let output: Data
        do {
            output = try processRunner(
                "/usr/bin/hdiutil",
                ["attach", "-plist", "-nobrowse", "-noautoopen", diskImageURL.path]
            )
        } catch {
            throw UpdateError.mountFailed(
                processFailureMessage(from: error, defaultMessage: "No mount details were returned.")
            )
        }

        do {
            return try mountedVolumeURL(fromAttachOutput: output)
        } catch {
            let message = String(data: output, encoding: .utf8) ?? "No mount details were returned."
            throw UpdateError.mountFailed(message)
        }
    }

    nonisolated private static func detachDiskImage(at mountedVolumeURL: URL) throws {
        try detachDiskImage(
            at: mountedVolumeURL,
            processRunner: runProcess,
            sleep: { Thread.sleep(forTimeInterval: $0) }
        )
    }

    nonisolated static func detachDiskImage(
        at mountedVolumeURL: URL,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws {
        do {
            _ = try processRunner("/usr/bin/hdiutil", ["detach", mountedVolumeURL.path])
        } catch let initialError {
            guard shouldRetryDiskImageDetach(after: initialError) else {
                throw UpdateError.detachFailed(
                    processFailureMessage(
                        from: initialError,
                        defaultMessage: "The installer disk image could not be detached."
                    )
                )
            }

            // Finder and Spotlight can briefly keep the mounted volume busy after we copy from it.
            sleep(diskImageDetachRetryDelay)

            do {
                _ = try processRunner("/usr/bin/hdiutil", ["detach", "-force", mountedVolumeURL.path])
            } catch let forcedError {
                throw UpdateError.detachFailed(
                    processFailureMessage(
                        from: forcedError,
                        fallback: processFailureMessage(
                            from: initialError,
                            defaultMessage: "The installer disk image could not be detached."
                        )
                    )
                )
            }
        }
    }

    nonisolated static func mountedVolumeURL(fromAttachOutput output: Data) throws -> URL {
        let propertyList = try PropertyListSerialization.propertyList(from: output, format: nil)
        guard let root = propertyList as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else {
            throw UpdateError.mountedVolumeNotFound
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }

        throw UpdateError.mountedVolumeNotFound
    }

    nonisolated private static func locateAppBundle(in mountedVolumeURL: URL, named expectedAppName: String) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: mountedVolumeURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app", item.lastPathComponent == expectedAppName {
                return item
            }
        }

        throw UpdateError.appBundleNotFound
    }

    nonisolated private static func validateInstalledApp(
        at appURL: URL,
        expectedAppName: String,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        guard appURL.lastPathComponent == expectedAppName else {
            throw UpdateError.invalidInstallerBundle(
                "The downloaded installer contained '\(appURL.lastPathComponent)' instead of '\(expectedAppName)'."
            )
        }

        guard let bundle = Bundle(url: appURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateError.invalidInstallerBundle(
                "The downloaded installer does not contain the expected DocNest app bundle."
            )
        }

        try verifyCodeSignature(
            of: appURL,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
    }

    nonisolated private static func currentTeamIdentifier(for appURL: URL) -> String? {
        try? codesignMetadata(for: appURL).teamIdentifier
    }

    nonisolated private static func verifyCodeSignature(
        of appURL: URL,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        try verifyCodeSignature(
            of: appURL,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier,
            processRunner: runProcess,
            metadataProvider: codesignMetadata
        )
    }

    nonisolated static func verifyCodeSignature(
        of appURL: URL,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data,
        metadataProvider: (_ appURL: URL) throws -> (identifier: String?, teamIdentifier: String?)
    ) throws {
        do {
            _ = try processRunner(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", appURL.path]
            )
        } catch {
            throw UpdateError.signatureValidationFailed(
                processFailureMessage(from: error, defaultMessage: "The app signature could not be verified.")
            )
        }

        let metadata = try metadataProvider(appURL)
        if let signingIdentifier = metadata.identifier,
           signingIdentifier != expectedBundleIdentifier {
            throw UpdateError.signatureValidationFailed(
                "Expected signing identifier \(expectedBundleIdentifier), got \(signingIdentifier)."
            )
        }

        if let expectedTeamIdentifier,
           let actualTeamIdentifier = metadata.teamIdentifier,
           actualTeamIdentifier != expectedTeamIdentifier {
            throw UpdateError.signatureValidationFailed(
                "Expected team identifier \(expectedTeamIdentifier), got \(actualTeamIdentifier)."
            )
        }
    }

    nonisolated private static func codesignMetadata(for appURL: URL) throws -> (identifier: String?, teamIdentifier: String?) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--verbose=4", appURL.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "The app code signature could not be inspected."
            throw UpdateError.signatureValidationFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let diagnostics = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return (
            identifier: codesignField(named: "Identifier", in: diagnostics),
            teamIdentifier: codesignField(named: "TeamIdentifier", in: diagnostics)
        )
    }

    nonisolated private static func codesignField(named name: String, in diagnostics: String) -> String? {
        for line in diagnostics.split(whereSeparator: \.isNewline) {
            let prefix = "\(name)="
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    nonisolated private static func processFailureMessage(from error: Error) -> String? {
        let message: String
        if let processError = error as? ProcessExecutionError {
            message = processError.message
        } else if let localizedDescription = (error as? LocalizedError)?.errorDescription {
            message = localizedDescription
        } else {
            message = error.localizedDescription
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func processFailureMessage(from error: Error, defaultMessage: String) -> String {
        processFailureMessage(from: error) ?? defaultMessage
    }

    nonisolated private static func processFailureMessage(from error: Error, fallback: String) -> String {
        processFailureMessage(from: error) ?? fallback
    }

    nonisolated private static func shouldRetryDiskImageDetach(after error: Error) -> Bool {
        guard let message = processFailureMessage(from: error)?.lowercased() else {
            return false
        }

        return message.contains("resource busy")
            || message.contains("couldn't unmount")
            || message.contains("couldnt unmount")
    }

    nonisolated private static func launchInstaller(_ preparedInstaller: PreparedInstaller) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [preparedInstaller.scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw UpdateError.installerLaunchFailed
        }
    }

    nonisolated private static func runProcess(executablePath: String, arguments: [String]) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData.isEmpty ? outputData : errorData, encoding: .utf8) ?? executablePath
            throw ProcessExecutionError(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return outputData
    }

    nonisolated static func installerScript(
        currentPID: Int32,
        stagedAppURL: URL,
        destinationAppURL: URL,
        temporaryRootURL: URL
    ) -> String {
        let stagedPath = shellQuoted(stagedAppURL.path)
        let destinationPath = shellQuoted(destinationAppURL.path)
        let temporaryRootPath = shellQuoted(temporaryRootURL.path)
        let replaceFunction = replaceFunctionScript()
        let privilegedCommand = """
        set -eu
        STAGED_APP=\(stagedPath)
        DESTINATION_APP=\(destinationPath)
        \(replaceFunction)
        install_update
        """

        let privilegedAppleScript = appleScriptQuoted(privilegedCommand)

        return """
        #!/bin/sh
        set -eu

        CURRENT_PID=\(currentPID)
        STAGED_APP=\(stagedPath)
        DESTINATION_APP=\(destinationPath)
        TEMP_ROOT=\(temporaryRootPath)

        \(replaceFunction)

        wait_for_app_exit() {
          ATTEMPTS=0
          while /bin/kill -0 "$CURRENT_PID" 2>/dev/null; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ "$ATTEMPTS" -gt 120 ]; then
              break
            fi
            /bin/sleep 1
          done
        }

        wait_for_app_exit

        if ! install_update; then
          /usr/bin/osascript -e "do shell script \(privilegedAppleScript) with administrator privileges"
        fi

        if [ ! -d "$DESTINATION_APP" ]; then
          exit 1
        fi

        /usr/bin/open "$DESTINATION_APP"
        /bin/rm -rf "$TEMP_ROOT"
        """
    }

    nonisolated private static func replaceFunctionScript() -> String {
        """
        install_update() {
          /bin/rm -rf "$DESTINATION_APP.new"
          /usr/bin/ditto "$STAGED_APP" "$DESTINATION_APP.new"
          /bin/rm -rf "$DESTINATION_APP.previous"
          if [ -e "$DESTINATION_APP" ]; then
            /bin/mv "$DESTINATION_APP" "$DESTINATION_APP.previous"
          fi
          if /bin/mv "$DESTINATION_APP.new" "$DESTINATION_APP"; then
            /bin/rm -rf "$DESTINATION_APP.previous"
            return 0
          fi
          /bin/rm -rf "$DESTINATION_APP"
          if [ -e "$DESTINATION_APP.previous" ]; then
            /bin/mv "$DESTINATION_APP.previous" "$DESTINATION_APP"
          fi
          return 1
        }
        """
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    nonisolated private static func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private struct AboutView: View {
    private let releaseVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    @StateObject private var updateService = AppUpdateService.shared
    @State private var statistics: LibrarySessionController.LibraryStatistics?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)

                    Text("DocNest")
                        .font(AppTypography.titleLarge)

                    Text("Version \(releaseVersion) • Build \(buildNumber)")
                        .font(AppTypography.settingsSubtitle)
                        .foregroundStyle(.secondary)

                    Button("Check for Updates…") {
                        updateService.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateService.isBusy)
                    .padding(.top, 4)

                    if let progress = updateService.updateProgress {
                        updateProgressCard(progress)
                    }

                    if let message = updateStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                aboutCard {
                    VStack(spacing: 4) {
                        Text("Developed by")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text("Christian Kaps")
                            .font(.body.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }

                aboutCard {
                    if let stats = statistics {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Library")
                                .font(.headline)

                            statisticRow("Path", value: stats.path, isPath: true)
                            statisticRow("Documents", value: "\(stats.documentCount)")
                            statisticRow("Document Size", value: stats.formattedTotalFileSize)
                            statisticRow("Library Size", value: stats.formattedPackageSize)
                        }
                    } else {
                        Text("No library open")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("© 2025 Christian Kaps. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(24)
        }
        .frame(width: 360)
        .onAppear {
            loadStatistics()
        }
    }

    private func statisticRow(_ label: String, value: String, isPath: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isPath {
                Text(value)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(value)
            } else {
                Text(value)
                    .font(.body.weight(.medium))
            }
        }
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private func updateProgressCard(_ progress: AppUpdateService.UpdateProgress) -> some View {
        aboutCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if progress.fractionCompleted == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.title)
                            .font(AppTypography.captionStrong)

                        Text(progress.detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(progress.statusSummary)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let fractionCompleted = progress.fractionCompleted {
                    ProgressView(value: fractionCompleted)
                        .progressViewStyle(.linear)
                }
            }
        }
        .transition(.opacity)
    }

    private func loadStatistics() {
        Task { @MainActor in
            statistics = await AboutStatisticsProvider.shared.controller?.libraryStatistics()
        }
    }

    private var updateStatusMessage: String? {
        switch updateService.status {
        case .idle:
            return nil
        case .checking:
            return "Checking GitHub releases…"
        case .downloading(let version):
            return updateService.updateProgress == nil ? "Downloading version \(version)…" : nil
        case .installing(let version):
            return updateService.updateProgress == nil
                ? "Installing version \(version). DocNest will relaunch automatically."
                : nil
        case .upToDate(let version):
            return "Installed version \(version) is current."
        case .updateAvailable(let info):
            return "Version \(info.latestVersion) is ready to install."
        case .failed(let message):
            return message
        }
    }
}

private struct AppSettingsRootView: View {
    @ObservedObject private var settings = AppSettingsController.shared

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 210)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settings.selectedPane.title)
                            .font(AppTypography.settingsTitle)

                        Text(settings.selectedPane.subtitle)
                            .font(AppTypography.settingsSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                    settingsDetailContent
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder
    private var settingsDetailContent: some View {
        switch settings.selectedPane {
        case .ocr:
            OCRSettingsView()
        case .labels:
            if let coordinator = settings.libraryCoordinator,
               let modelContainer = settings.modelContainer {
                LabelManagerSheet(showsDoneButton: false)
                    .environment(coordinator)
                    .modelContainer(modelContainer)
            } else {
                unavailableLibrarySettingsView
            }
        case .watchFolders:
            if let coordinator = settings.libraryCoordinator,
               let modelContainer = settings.modelContainer {
                WatchFolderSettingsView(showsDoneButton: false)
                    .environment(coordinator)
                    .modelContainer(modelContainer)
            } else {
                unavailableLibrarySettingsView
            }
        }
    }

    private var unavailableLibrarySettingsView: some View {
        ContentUnavailableView(
            "No Library Open",
            systemImage: "books.vertical",
            description: Text("Open a DocNest library to manage labels and watch folders in Settings.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: selectedPaneBinding) {
                ForEach(AppSettingsPane.allCases) { pane in
                    settingsSidebarRow(for: pane)
                        .tag(pane)
                        .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 8)
            }
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    private var selectedPaneBinding: Binding<AppSettingsPane?> {
        Binding(
            get: { settings.selectedPane },
            set: { if let newValue = $0 { settings.selectedPane = newValue } }
        )
    }

    private func settingsSidebarRow(for pane: AppSettingsPane) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(settings.selectedPane == pane ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.body.weight(.medium))

                Text(pane.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct OCRSettingsView: View {
    @AppStorage(OCRBackend.defaultsKey) private var selectedBackend = OCRBackend.automatic.rawValue

    private var backendBinding: Binding<OCRBackend> {
        Binding(
            get: { OCRBackend(rawValue: selectedBackend) ?? .automatic },
            set: { selectedBackend = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose how DocNest extracts searchable text from imported and backfilled PDFs.")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("OCR Engine", selection: backendBinding) {
                ForEach(OCRBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                ForEach(OCRBackend.allCases) { backend in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(backend.title)
                                .font(.headline)

                            if backend == backendBinding.wrappedValue {
                                Text("Selected")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                        }

                        Text(backend.summary)
                            .font(.subheadline)

                        Text(backend.availabilityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }
}

private struct HelpView: View {
    private struct HelpSection: Identifiable {
        let id: String
        let title: String
        let body: [String]
    }

    private let overview = [
        "DocNest is a local-first document library for PDFs. A library is stored as a single .docnestlibrary package that contains your indexed metadata, managed files, previews, and diagnostics.",
        "The main window uses a three-column layout: the sidebar on the left for navigation and filters, the document list or grid in the center, and the inspector on the right for details and editing.",
        "Most commands are intentionally close to where you use them: quick actions live in menus and context menus, while broader management tools now live in Settings."
    ]

    private let sections: [HelpSection] = [
        HelpSection(
            id: "start",
            title: "Getting Started",
            body: [
                "Choose File > Create Library to make a new library package, or File > Open Library to open an existing one.",
                "After a library is open, drag PDFs or folders into the app, use Open With from Finder, use Services from other apps, or let watch folders import automatically.",
                "DocNest ignores attempts to import the open library package itself or one of its internal folders, which helps avoid accidental self-import loops."
            ]
        ),
        HelpSection(
            id: "library",
            title: "Working With Libraries",
            body: [
                "A library package is the container for your complete DocNest collection. You can reveal it in Finder with File > Show in Finder.",
                "DocNest keeps working data inside the package, runs integrity checks when libraries open, and writes diagnostics so integrity problems are easier to spot early.",
                "If library structure or derived metadata can be repaired safely, DocNest performs conservative self-healing and records what it repaired in the diagnostics report."
            ]
        ),
        HelpSection(
            id: "organize",
            title: "Organizing Documents",
            body: [
                "Use labels to tag documents across projects, clients, topics, or workflows. Assign labels from Edit > Assign Labels or manage the full label list from DocNest > Settings… > Labels.",
                "Smart folders give you saved filtered views. They live in the sidebar and update automatically when matching documents change.",
                "The Labels section in the sidebar has a dedicated button for new labels and a separate button for new label groups, so creating groups no longer requires an extra menu step.",
                "The inspector is the place to edit document title, notes, detected date, labels, and other metadata for the current selection."
            ]
        ),
        HelpSection(
            id: "search",
            title: "Search and Filtering",
            body: [
                "Use Edit > Find or Command-F to focus the search field.",
                "Sidebar labels act as filters. You can combine multiple labels to narrow the document list. Smart folders and library sections also change the current result set.",
                "Command-A selects the documents in the current filtered result set, not every document in the library."
            ]
        ),
        HelpSection(
            id: "document-list",
            title: "Document List and Renaming",
            body: [
                "Select a document once to focus it. Double-click the selected document name to rename it inline.",
                "You can also right-click a document and choose Rename from the context menu.",
                "Press Return to confirm a rename or Escape to cancel editing."
            ]
        ),
        HelpSection(
            id: "watch-folders",
            title: "Watch Folders",
            body: [
                "Watch folders monitor selected Finder folders and automatically import new PDFs into the current library.",
                "Open them from DocNest > Settings… > Watch Folders to add, edit, pause, resume, or remove a monitored folder.",
                "DocNest blocks unsafe watch folders that point to the open library package or one of its subfolders."
            ]
        ),
        HelpSection(
            id: "appearance",
            title: "Appearance and App Settings",
            body: [
                "DocNest keeps settings intentionally focused. Use DocNest > Settings… or Command-Comma to open the Settings window.",
                "The main app setting is Appearance. Use the toolbar button with the half-filled circle icon to switch between System, Light, and Dark.",
                "Settings currently includes dedicated panes for Labels and Watch Folders.",
                "Use the Labels pane for full label and label-group management. Use the Watch Folders pane to control monitored import locations."
            ]
        ),
        HelpSection(
            id: "safety",
            title: "Safety, Recovery, and Diagnostics",
            body: [
                "DocNest writes integrity diagnostics for library consistency so issues are easier to detect early.",
                "If a file is missing or metadata needs repair, DocNest tries conservative self-healing first and records remaining warnings in the library diagnostics report."
            ]
        )
    ]

    private let locations: [(String, String)] = [
        ("Create a new library", "File > Create Library"),
        ("Open an existing library", "File > Open Library"),
        ("Reveal the current library in Finder", "File > Show in Finder"),
        ("Close the current library", "File > Close Library"),
        ("Export selected documents", "File > Export… or Shift-Command-E"),
        ("Import from another app", "Open With DocNest or Services / Share menu for supported files"),
        ("Find/search", "Edit > Find or Command-F"),
        ("Assign labels to the selection", "Edit > Assign Labels or Command-L"),
        ("Select all visible filtered documents", "Edit > Select All or Command-A"),
        ("Rename a document", "Double-click the selected name, or use the document context menu"),
        ("Open Settings", "DocNest > Settings… or Command-Comma"),
        ("Open full label management", "DocNest > Settings… > Labels"),
        ("Configure watch folders", "DocNest > Settings… > Watch Folders"),
        ("Switch appearance", "Toolbar > Appearance button"),
        ("Open About", "DocNest > About DocNest"),
        ("Open this help guide", "Help > DocNest Help")
    ]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    sectionCard(title: "Overview", items: overview)

                    ForEach(sections) { section in
                        sectionCard(title: section.title, items: section.body)
                    }

                    locationsBlock
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DocNest Help")
                .font(AppTypography.titleLarge)

            Text("A quick guide to the app, the library workflow, and where to find important commands and settings.")
                .font(AppTypography.settingsSubtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionCard(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionTitle)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(AppTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var locationsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where to Find Things")
                .font(AppTypography.sectionTitle)

            Text("DocNest uses a small set of menus and contextual controls instead of a large settings window. This table points you to the right place quickly.")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(locations, id: \.0) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Text(item.0)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 250, alignment: .leading)

                        Text(item.1)
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)

                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Statistics Provider

/// A lightweight bridge so the About panel can access library statistics
/// without tight coupling to the view hierarchy.
@MainActor
final class AboutStatisticsProvider {
    static let shared = AboutStatisticsProvider()
    weak var controller: LibrarySessionController?
    private init() {}
}
