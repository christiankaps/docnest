import AppKit
import SwiftUI
import SwiftData

struct WatchFolderEditorConfig: Identifiable {
    let id = UUID()
    let mode: Mode
    let prefillFolderPath: String?

    enum Mode {
        case create
        case edit(WatchFolder)
    }

    init(mode: Mode, prefillFolderPath: String? = nil) {
        self.mode = mode
        self.prefillFolderPath = prefillFolderPath
    }
}

struct WatchFolderEditorSheet: View {
    let config: WatchFolderEditorConfig

    @Environment(LibraryCoordinator.self) private var coordinator
    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)])
    private var allLabels: [LabelTag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var folderPath: String = ""
    @State private var isEnabled: Bool = true
    @State private var selectedLabelIDs: Set<UUID> = []
    @State private var newLabelName: String = ""
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = config.mode { return true }
        return false
    }

    private var existingFolder: WatchFolder? {
        if case .edit(let folder) = config.mode { return folder }
        return nil
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folderPath.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Watch Folder" : "New Watch Folder")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Form {
                // Name + Icon
                HStack(spacing: 8) {
                    EmojiPickerButton(selection: $icon)
                        .frame(width: 28, height: 22)
                        .help("Choose emoji icon (optional)")

                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Folder path
                Section("Folder") {
                    HStack {
                        Text(folderPath.isEmpty ? "No folder selected" : folderPath)
                            .font(.system(size: 12))
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose\u{2026}") {
                            chooseFolder()
                        }
                    }
                }

                // Enable toggle
                Toggle("Enabled", isOn: $isEnabled)

                // Label auto-assign
                Section("Auto-assign Labels") {
                    ForEach(allLabels) { label in
                        let isSelected = selectedLabelIDs.contains(label.id)
                        Button {
                            if isSelected {
                                selectedLabelIDs.remove(label.id)
                            } else {
                                selectedLabelIDs.insert(label.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                                if let labelIcon = label.icon, !labelIcon.isEmpty {
                                    Text(labelIcon)
                                        .font(.system(size: 12))
                                } else {
                                    Circle()
                                        .fill(label.labelColor.color)
                                        .frame(width: 8, height: 8)
                                }

                                Text(label.name)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        TextField("New label", text: $newLabelName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { createNewLabel() }

                        Button {
                            createNewLabel()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            // Action buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Create") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .frame(width: 380, height: 480)
        .onAppear {
            if let folder = existingFolder {
                name = folder.name
                icon = folder.icon ?? ""
                folderPath = folder.folderPath
                isEnabled = folder.isEnabled
                selectedLabelIDs = Set(folder.labelIDs)
            } else if let prefillPath = config.prefillFolderPath {
                folderPath = prefillPath
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = URL(fileURLWithPath: prefillPath).lastPathComponent
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder to watch for new PDFs."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        folderPath = url.path
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent
        }
    }

    private func createNewLabel() {
        let trimmed = newLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let label = try ManageLabelsUseCase.createLabel(named: trimmed, color: .blue, using: modelContext)
            selectedLabelIDs.insert(label.id)
            newLabelName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let labelIDArray = allLabels.compactMap { label in
                selectedLabelIDs.contains(label.id) ? label.id : nil
            }

            if let folder = existingFolder {
                try ManageWatchFoldersUseCase.update(
                    folder,
                    name: name,
                    icon: icon.isEmpty ? nil : String(icon.prefix(1)),
                    folderPath: folderPath,
                    libraryURL: coordinator.libraryURL,
                    isEnabled: isEnabled,
                    labelIDs: labelIDArray,
                    using: modelContext
                )
            } else {
                try ManageWatchFoldersUseCase.create(
                    named: name,
                    icon: icon.isEmpty ? nil : String(icon.prefix(1)),
                    folderPath: folderPath,
                    libraryURL: coordinator.libraryURL,
                    labelIDs: labelIDArray,
                    using: modelContext
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
