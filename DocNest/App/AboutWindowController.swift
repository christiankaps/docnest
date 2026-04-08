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
    case labels
    case watchFolders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .labels: "Labels"
        case .watchFolders: "Watch Folders"
        }
    }

    var systemImage: String {
        switch self {
        case .labels: "tag"
        case .watchFolders: "folder.badge.gearshape"
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 420)

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

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(AppReleaseVersion)
        case updateAvailable(AppUpdateInfo)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private let owner = "christiankaps"
    private let repo = "docnest"

    private init() {}

    func checkForUpdates(userInitiated: Bool = true) {
        guard status != .checking else { return }

        status = .checking

        Task {
            do {
                let info = try await fetchUpdateInfo()
                if let info {
                    status = .updateAvailable(info)
                    if userInitiated {
                        presentUpdateAlert(info)
                    }
                } else if let currentVersion = currentInstalledVersion() {
                    status = .upToDate(currentVersion)
                    if userInitiated {
                        presentInformationalAlert(
                            title: "DocNest Is Up to Date",
                            message: "You already have the latest released version installed."
                        )
                    }
                } else {
                    status = .idle
                    if userInitiated {
                        presentInformationalAlert(
                            title: "Version Check Finished",
                            message: "No newer GitHub release was found."
                        )
                    }
                }
            } catch {
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

    func openDownload(_ info: AppUpdateInfo) {
        NSWorkspace.shared.open(info.downloadURL)
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
        let dmgAsset = response.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
        let downloadURL = URL(string: dmgAsset?.browserDownloadURL ?? response.htmlURL) ?? releasePageURL

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL,
            assetName: dmgAsset?.name
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
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Release Page")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openDownload(info)
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

    private enum UpdateError: LocalizedError {
        case invalidInstalledVersion
        case invalidRemoteVersion(String)
        case invalidResponse
        case httpStatus(Int)
        case invalidPayload

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
            }
        }
    }
}

private struct AboutView: View {
    private let releaseVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    @StateObject private var updateService = AppUpdateService.shared
    @State private var statistics: LibrarySessionController.LibraryStatistics?

    var body: some View {
        VStack(spacing: 0) {
            // App icon and name
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("DocNest")
                    .font(.system(size: 22, weight: .semibold))

                Text("Version \(releaseVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Build \(buildNumber)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("Check for Updates…") {
                    updateService.checkForUpdates()
                }
                .padding(.top, 4)

                if let message = updateStatusMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 24)

            // Credits
            VStack(spacing: 4) {
                Text("Developed by")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text("Christian Kaps")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.vertical, 12)

            // Library statistics
            if let stats = statistics {
                Divider()
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Library")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    statisticRow("Path", value: stats.path, isPath: true)
                    statisticRow("Documents", value: "\(stats.documentCount)")
                    statisticRow("Document Size", value: stats.formattedTotalFileSize)
                    statisticRow("Library Size", value: stats.formattedPackageSize)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            } else {
                Divider()
                    .padding(.horizontal, 24)

                Text("No library open")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }

            // Copyright
            Text("© 2025 Christian Kaps. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(width: 360)
        .onAppear {
            loadStatistics()
        }
    }

    private func statisticRow(_ label: String, value: String, isPath: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
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
                    .font(.system(size: 12, weight: .medium))
            }
        }
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
        case .upToDate(let version):
            return "Installed version \(version) is current."
        case .updateAvailable(let info):
            return "Version \(info.latestVersion) is available to download."
        case .failed(let message):
            return message
        }
    }
}

private struct AppSettingsRootView: View {
    @ObservedObject private var settings = AppSettingsController.shared

    var body: some View {
        Group {
            if let coordinator = settings.libraryCoordinator,
               let modelContainer = settings.modelContainer {
                TabView(selection: $settings.selectedPane) {
                    LabelManagerSheet(showsDoneButton: false)
                        .environment(coordinator)
                        .modelContainer(modelContainer)
                        .tabItem {
                            Label(AppSettingsPane.labels.title, systemImage: AppSettingsPane.labels.systemImage)
                        }
                        .tag(AppSettingsPane.labels)

                    WatchFolderSettingsView(showsDoneButton: false)
                        .environment(coordinator)
                        .modelContainer(modelContainer)
                        .tabItem {
                            Label(AppSettingsPane.watchFolders.title, systemImage: AppSettingsPane.watchFolders.systemImage)
                        }
                        .tag(AppSettingsPane.watchFolders)
                }
                .padding(.top, 8)
            } else {
                ContentUnavailableView(
                    "No Library Open",
                    systemImage: "books.vertical",
                    description: Text("Open a DocNest library to manage labels and watch folders in Settings.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
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
        "The main window uses a three-column layout: the sidebar on the left for navigation and filters, the document list or grid in the center, and the inspector on the right for details and editing."
    ]

    private let sections: [HelpSection] = [
        HelpSection(
            id: "start",
            title: "Getting Started",
            body: [
                "Choose File > Create Library to make a new library package, or File > Open Library to open an existing one.",
                "After a library is open, drag PDFs or folders into the app, use Open With from Finder, or let watch folders import automatically."
            ]
        ),
        HelpSection(
            id: "library",
            title: "Working With Libraries",
            body: [
                "A library package is the container for your complete DocNest collection. You can reveal it in Finder with File > Show in Finder.",
                "DocNest keeps working data inside the package, runs integrity checks when libraries open, and avoids importing the library into itself."
            ]
        ),
        HelpSection(
            id: "organize",
            title: "Organizing Documents",
            body: [
                "Use labels to tag documents across projects, clients, topics, or workflows. Assign labels from Edit > Assign Labels or manage the full label list from DocNest > Settings… > Labels.",
                "Smart folders give you saved filtered views. They live in the sidebar and update automatically when matching documents change.",
                "The inspector is the place to edit document title, notes, detected date, labels, and other metadata for the current selection."
            ]
        ),
        HelpSection(
            id: "search",
            title: "Search and Filtering",
            body: [
                "Use Edit > Find or Command-F to focus the search field.",
                "Sidebar labels act as filters. You can combine multiple labels to narrow the document list. Smart folders and library sections also change the current result set."
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
                "Settings currently includes dedicated panes for Labels and Watch Folders, while other controls remain contextual in the sidebar and inspector."
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
        ("Find/search", "Edit > Find or Command-F"),
        ("Assign labels to the selection", "Edit > Assign Labels or Command-L"),
        ("Open Settings", "DocNest > Settings… or Command-Comma"),
        ("Open full label management", "DocNest > Settings… > Labels"),
        ("Configure watch folders", "DocNest > Settings… > Watch Folders"),
        ("Switch appearance", "Toolbar > Appearance button"),
        ("Open About", "DocNest > About DocNest"),
        ("Open this help guide", "Help > DocNest Help")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                sectionBlock(title: "Overview", items: overview)

                ForEach(sections) { section in
                    sectionBlock(title: section.title, items: section.body)
                }

                locationsBlock
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DocNest Help")
                .font(.system(size: 28, weight: .semibold))

            Text("A quick guide to the app, the library workflow, and where to find important commands and settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var locationsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where to Find Things")
                .font(.system(size: 16, weight: .semibold))

            Text("DocNest uses a small set of menus and contextual controls instead of a large settings window. This table points you to the right place quickly.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(locations, id: \.0) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Text(item.0)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 250, alignment: .leading)

                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)

                    Divider()
                }
            }
        }
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
