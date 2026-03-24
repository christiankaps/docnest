import AppKit
import SwiftUI
import SwiftData

struct WatchFolderSettingsView: View {
    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editorConfig: WatchFolderEditorConfig?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Watch Folders")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 4)

            Text("Watched folders are monitored for new PDFs, which are automatically imported into the library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if coordinator.allWatchFolders.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Watch Folders", systemImage: "eye.slash")
                } description: {
                    Text("Add a folder to start automatically importing PDFs.")
                }
                Spacer()
            } else {
                List {
                    ForEach(coordinator.allWatchFolders) { folder in
                        WatchFolderRow(
                            folder: folder,
                            status: coordinator.watchFolderStatuses[folder.id] ?? .paused,
                            onEdit: { editorConfig = WatchFolderEditorConfig(mode: .edit(folder)) },
                            onToggleEnabled: { toggleEnabled(folder) },
                            onRevealInFinder: { revealInFinder(folder) },
                            onDelete: { deleteWatchFolder(folder) }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            HStack {
                Button {
                    promptAndAddWatchFolder()
                } label: {
                    Label("Add Folder\u{2026}", systemImage: "plus")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 420)
        .sheet(item: $editorConfig) { config in
            WatchFolderEditorSheet(config: config)
        }
        .alert("Watch Folder Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func promptAndAddWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder to watch for new PDFs."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        editorConfig = WatchFolderEditorConfig(
            mode: .create,
            prefillFolderPath: url.path
        )
    }

    private func toggleEnabled(_ folder: WatchFolder) {
        do {
            try ManageWatchFoldersUseCase.setEnabled(folder, enabled: !folder.isEnabled, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revealInFinder(_ folder: WatchFolder) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.folderPath)
    }

    private func deleteWatchFolder(_ folder: WatchFolder) {
        do {
            try ManageWatchFoldersUseCase.delete(folder, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WatchFolderRow: View {
    let folder: WatchFolder
    let status: WatchFolderStatus
    let onEdit: () -> Void
    let onToggleEnabled: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void

    private var statusIcon: String {
        switch status {
        case .monitoring: "eye.fill"
        case .paused: "pause.circle"
        case .pathInvalid: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .monitoring: .green
        case .paused: .secondary
        case .pathInvalid: .orange
        }
    }

    private var statusLabel: String {
        switch status {
        case .monitoring: "Monitoring"
        case .paused: "Paused"
        case .pathInvalid: "Path not found"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = folder.icon, !icon.isEmpty {
                Text(icon)
                    .font(.title2)
                    .frame(width: 28)
            } else {
                Image(systemName: "folder.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .fontWeight(.medium)

                Text(folder.folderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit\u{2026}") { onEdit() }

            Button(folder.isEnabled ? "Pause" : "Resume") { onToggleEnabled() }

            Button("Reveal in Finder") { onRevealInFinder() }

            Divider()

            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
