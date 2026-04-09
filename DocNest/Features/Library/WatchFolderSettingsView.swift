import AppKit
import SwiftUI
import SwiftData

struct WatchFolderSettingsView: View {
    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = true

    @State private var editorConfig: WatchFolderEditorConfig?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            header

            Group {
                if coordinator.allWatchFolders.isEmpty {
                    ContentUnavailableView {
                        Label("No Watch Folders", systemImage: "eye.slash")
                    } description: {
                        Text("Add a folder to start automatically importing PDFs.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settingsPaneSurface)
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
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(settingsPaneSurface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack {
                Button {
                    promptAndAddWatchFolder()
                } label: {
                    Label("Add Folder\u{2026}", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if showsDoneButton {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watch Folders")
                .font(.title2.weight(.semibold))

            Text("Monitor Finder folders and import new PDFs automatically into the current library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsPaneSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
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
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            } else {
                Image(systemName: "folder.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body.weight(.medium))

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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.12))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
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
