import SwiftUI
import SwiftData

struct SmartFolderEditorSheet: View {
    let config: SmartFolderEditorConfig
    let allLabels: [LabelTag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var selectedLabelIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = config.mode { return true }
        return false
    }

    private var existingFolder: SmartFolder? {
        if case .edit(let folder) = config.mode { return folder }
        return nil
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(isEditing ? "Edit Smart Folder" : "New Smart Folder")
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

                // Label criteria
                if !allLabels.isEmpty {
                    Section("Labels") {
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

                                    if let icon = label.icon, !icon.isEmpty {
                                        Text(icon)
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
        .frame(width: 380, height: 420)
        .onAppear {
            if let folder = existingFolder {
                name = folder.name
                icon = folder.icon ?? ""
                selectedLabelIDs = Set(folder.labelIDs)
            } else {
                selectedLabelIDs = Set(config.prefillLabelIDs)
            }
        }
    }

    private func save() {
        do {
            let labelIDArray = allLabels.compactMap { label in
                selectedLabelIDs.contains(label.id) ? label.id : nil
            }

            if let folder = existingFolder {
                try ManageSmartFoldersUseCase.update(
                    folder,
                    name: name,
                    icon: icon.isEmpty ? nil : String(icon.prefix(1)),
                    labelIDs: labelIDArray,
                    using: modelContext
                )
            } else {
                try ManageSmartFoldersUseCase.create(
                    named: name,
                    icon: icon.isEmpty ? nil : String(icon.prefix(1)),
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
