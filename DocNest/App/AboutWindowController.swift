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
        fatalError()
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - About View

private struct AboutView: View {
    private let appVersion: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }()

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

                Text("Version \(appVersion)")
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

    @MainActor
    private func loadStatistics() {
        statistics = AboutStatisticsProvider.shared.controller?.libraryStatistics()
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
