import SwiftUI
import SwiftData

struct LabelEditorConfig: Identifiable {
    let id = UUID()
    let mode: Mode

    enum Mode {
        case create(groupID: UUID?)
        case edit(LabelTag)
    }
}

struct LabelEditorSheet: View {
    let config: LabelEditorConfig
    let allGroups: [LabelGroup]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var selectedColor: LabelColor = .blue
    @State private var selectedGroupID: UUID?
    @State private var isCreatingNewGroup = false
    @State private var newGroupName = ""
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = config.mode { return true }
        return false
    }

    private var existingLabel: LabelTag? {
        if case .edit(let label) = config.mode { return label }
        return nil
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Label" : "New Label")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Form {
                // Name + Icon
                HStack(spacing: 8) {
                    EmojiPickerButton(selection: $icon)
                        .frame(width: 28, height: 22)
                        .help("Choose emoji icon (optional)")

                    TextField("Label name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Color grid
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5), spacing: 8) {
                        ForEach(LabelColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(color.color.opacity(0.4), lineWidth: 1)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 0.15), value: selectedColor)
                            }
                            .buttonStyle(.plain)
                            .help(color.displayName)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Group picker
                Section("Group") {
                    Picker("Group", selection: $selectedGroupID) {
                        Text("None").tag(UUID?.none)
                        ForEach(allGroups) { group in
                            Text(group.name).tag(UUID?.some(group.id))
                        }
                    }
                    .labelsHidden()

                    if isCreatingNewGroup {
                        HStack(spacing: 6) {
                            TextField("Group name", text: $newGroupName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { createNewGroup() }

                            Button("Add") { createNewGroup() }
                                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Cancel") {
                                isCreatingNewGroup = false
                                newGroupName = ""
                            }
                        }
                    } else {
                        Button("New Group\u{2026}") {
                            isCreatingNewGroup = true
                        }
                        .font(.caption)
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
            if let label = existingLabel {
                name = label.name
                icon = label.icon ?? ""
                selectedColor = label.labelColor
                selectedGroupID = label.groupID
            } else if case .create(let groupID) = config.mode {
                selectedGroupID = groupID
            }
        }
    }

    private func save() {
        do {
            let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
            let iconValue = trimmedIcon.isEmpty ? nil : String(trimmedIcon.prefix(1))

            if let label = existingLabel {
                try ManageLabelsUseCase.update(
                    label,
                    name: name,
                    color: selectedColor,
                    icon: iconValue,
                    groupID: selectedGroupID,
                    using: modelContext
                )
            } else {
                try ManageLabelsUseCase.createLabel(
                    named: name,
                    color: selectedColor,
                    icon: iconValue,
                    groupID: selectedGroupID,
                    using: modelContext
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createNewGroup() {
        do {
            let group = try ManageLabelGroupsUseCase.create(named: newGroupName, using: modelContext)
            selectedGroupID = group.id
            isCreatingNewGroup = false
            newGroupName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
