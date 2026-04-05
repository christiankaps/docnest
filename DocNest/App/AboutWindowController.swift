import AppKit
import SwiftUI

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

// MARK: - About View

private struct AboutView: View {
    private let releaseVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

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
                "Use labels to tag documents across projects, clients, topics, or workflows. Assign labels from Edit > Assign Labels or manage the full label list from Edit > Manage Labels…",
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
                "Open them from Edit > Watch Folders… to add, edit, pause, resume, or remove a monitored folder.",
                "DocNest blocks unsafe watch folders that point to the open library package or one of its subfolders."
            ]
        ),
        HelpSection(
            id: "appearance",
            title: "Appearance and App Settings",
            body: [
                "DocNest keeps settings intentionally small. There is currently no large preferences window.",
                "The main app setting is Appearance. Use the toolbar button with the half-filled circle icon to switch between System, Light, and Dark.",
                "Most other controls that feel like settings are contextual and live where you use them: label management, watch folders, smart folders, and inspector editing."
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
        ("Open full label management", "Edit > Manage Labels… or Shift-Command-L"),
        ("Configure watch folders", "Edit > Watch Folders…"),
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
