import SwiftUI
import SwiftData

struct LabelManagerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryCoordinator.self) private var coordinator
    var showsDoneButton = true

    // MARK: - Selection state

    @State private var selectedLabelIDs: Set<UUID> = []
    @State private var isCreatingLabel = false
    @State private var createInGroupID: UUID?

    // MARK: - Editor state (single label)

    @State private var editorName = ""
    @State private var editorIcon = ""
    @State private var editorColor: LabelColor = .blue
    @State private var editorGroupID: UUID?
    @State private var suppressAutoSave = false

    // MARK: - Group management

    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var renamingGroupID: UUID?
    @State private var renamingGroupName = ""

    // MARK: - Bulk group assignment

    @State private var bulkGroupID: UUID?

    // MARK: - Deletion confirmation

    @State private var isConfirmingDeletion = false
    @State private var deletionTarget: DeletionTarget?

    // MARK: - Error

    @State private var errorMessage: String?

    enum DeletionTarget {
        case labels(Set<UUID>)
        case group(LabelGroup)
    }

    // MARK: - Computed

    private var sortedLabels: [LabelTag] {
        coordinator.allLabels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private var ungroupedLabels: [LabelTag] {
        sortedLabels.filter { $0.groupID == nil }
    }

    private var sortedGroups: [LabelGroup] {
        coordinator.allLabelGroups.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func labelsInGroup(_ group: LabelGroup) -> [LabelTag] {
        sortedLabels.filter { $0.groupID == group.id }
    }

    private var singleSelectedLabel: LabelTag? {
        guard selectedLabelIDs.count == 1,
              let id = selectedLabelIDs.first else { return nil }
        return coordinator.allLabels.first { $0.id == id }
    }

    private var isSaveDisabled: Bool {
        editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 18) {
            header

            HStack(spacing: 0) {
                labelListPanel
                    .frame(width: 260)
                    .background(panelSurface)

                editorPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(panelSurface)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 660, minHeight: 480)
        .alert("New Group", isPresented: $isCreatingGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") { createGroup() }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Enter a name for the label group.")
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDeletion()
            }
            Button("Cancel", role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            Text(deletionDialogMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Labels")
                    .font(.title2.weight(.semibold))

                Text("Organize labels and groups for the current library. Changes here update the sidebar and document workflows immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if showsDoneButton {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Left panel: label list

    private var labelListPanel: some View {
        Group {
            if ungroupedLabels.isEmpty && sortedGroups.isEmpty {
                ContentUnavailableView("No Labels", systemImage: "tag", description: Text("Click + to create a label."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedLabelIDs) {
                    if !ungroupedLabels.isEmpty {
                        Section("Labels") {
                            ForEach(ungroupedLabels) { label in
                                labelRow(for: label)
                                    .tag(label.id)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }

                    ForEach(sortedGroups) { group in
                        Section {
                            ForEach(labelsInGroup(group)) { label in
                                labelRow(for: label)
                                    .tag(label.id)
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            groupHeader(for: group)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedLabelIDs) { _, newIDs in
                    if isCreatingLabel { return }
                    loadEditorFromSelection()
                }
            }
        }
    }

    private func labelRow(for label: LabelTag) -> some View {
        HStack(spacing: 6) {
            if let icon = label.icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 12))
                    .frame(width: 18, alignment: .center)
            } else {
                Circle()
                    .fill(label.labelColor.color)
                    .frame(width: 10, height: 10)
                    .frame(width: 18)
            }
            Text(label.name)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive) {
                deletionTarget = .labels([label.id])
                isConfirmingDeletion = true
            }
        }
    }

    private func groupHeader(for group: LabelGroup) -> some View {
        Group {
            if renamingGroupID == group.id {
                TextField("Group name", text: $renamingGroupName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitGroupRename(group) }
                    .onExitCommand { cancelGroupRename() }
            } else {
                Text(group.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Rename Group") {
                renamingGroupID = group.id
                renamingGroupName = group.name
            }
            Button("Add Label to Group") {
                beginCreateLabel(inGroup: group.id)
            }
            Divider()
            Button("Delete Group", role: .destructive) {
                deletionTarget = .group(group)
                isConfirmingDeletion = true
            }
        }
    }

    // MARK: - Right panel: editor

    @ViewBuilder
    private var editorPanel: some View {
        if isCreatingLabel {
            editorContainer(
                title: "New Label",
                subtitle: "Create a label with a name, color, optional emoji, and group."
            ) {
                createLabelEditor
            }
        } else if selectedLabelIDs.count > 1 {
            editorContainer(
                title: "Bulk Actions",
                subtitle: "Apply group changes or remove multiple labels at once."
            ) {
                bulkActionsPanel
            }
        } else if singleSelectedLabel != nil {
            editorContainer(
                title: "Label Details",
                subtitle: "Update the selected label and its grouping immediately."
            ) {
                singleLabelEditor
            }
        } else {
            editorContainer(
                title: "Select a Label",
                subtitle: "Choose a label from the list to edit it, or create a new one."
            ) {
                ContentUnavailableView(
                    "Select a Label",
                    systemImage: "tag",
                    description: Text("Select a label to edit, or click + to create a new one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Single label editor

    private var singleLabelEditor: some View {
        Form {
            HStack(spacing: 8) {
                EmojiPickerButton(selection: $editorIcon)
                    .frame(width: 28, height: 22)
                    .help("Choose emoji icon (optional)")

                TextField("Label name", text: $editorName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyChanges() }
            }
            .onChange(of: editorIcon) { autoSave() }

            Section("Color") {
                colorGrid
            }

            Section("Group") {
                groupPicker
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
    }

    // MARK: - Create label editor

    private var createLabelEditor: some View {
        Form {
            HStack(spacing: 8) {
                EmojiPickerButton(selection: $editorIcon)
                    .frame(width: 28, height: 22)
                    .help("Choose emoji icon (optional)")

                TextField("Label name", text: $editorName)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Color") {
                colorGrid
            }

            Section("Group") {
                groupPicker
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    isCreatingLabel = false
                    loadEditorFromSelection()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createLabel()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
    }

    // MARK: - Bulk actions panel

    private var bulkActionsPanel: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "tag.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("\(selectedLabelIDs.count) labels selected")
                .font(.headline)

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Text("Bulk Actions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Move to Group:")
                    Picker("", selection: $bulkGroupID) {
                        Text("None").tag(UUID?.none)
                        ForEach(sortedGroups) { group in
                            Text(group.name).tag(UUID?.some(group.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)

                    Button("Apply") {
                        bulkMoveToGroup()
                    }
                }

                Button("Delete Selected Labels", role: .destructive) {
                    deletionTarget = .labels(selectedLabelIDs)
                    isConfirmingDeletion = true
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            bulkGroupID = nil
        }
        .padding(20)
    }

    // MARK: - Shared editor components

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5), spacing: 8) {
            ForEach(LabelColor.allCases) { color in
                Button {
                    editorColor = color
                    autoSave()
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: editorColor == color ? 2.5 : 0)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(color.color.opacity(0.4), lineWidth: 1)
                        )
                        .scaleEffect(editorColor == color ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: editorColor)
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }
        }
        .padding(.vertical, 4)
    }

    private var groupPicker: some View {
        Picker("Group", selection: $editorGroupID) {
            Text("None").tag(UUID?.none)
            ForEach(sortedGroups) { group in
                Text(group.name).tag(UUID?.some(group.id))
            }
        }
        .labelsHidden()
        .onChange(of: editorGroupID) { autoSave() }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                beginCreateLabel(inGroup: nil)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help("New Label")

            Button {
                newGroupName = ""
                isCreatingGroup = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help("New Group")

            Button {
                deletionTarget = .labels(selectedLabelIDs)
                isConfirmingDeletion = true
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(selectedLabelIDs.isEmpty)
            .help("Delete selected labels")

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var panelSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func editorContainer<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func loadEditorFromSelection() {
        errorMessage = nil
        if let label = singleSelectedLabel {
            suppressAutoSave = true
            editorName = label.name
            editorIcon = label.icon ?? ""
            editorColor = label.labelColor
            editorGroupID = label.groupID
            suppressAutoSave = false
        }
    }

    private func beginCreateLabel(inGroup groupID: UUID?) {
        suppressAutoSave = true
        selectedLabelIDs.removeAll()
        isCreatingLabel = true
        createInGroupID = groupID
        editorName = ""
        editorIcon = ""
        editorColor = .blue
        editorGroupID = groupID
        errorMessage = nil
        suppressAutoSave = false
    }

    private func createLabel() {
        do {
            let trimmedIcon = editorIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            let iconValue = trimmedIcon.isEmpty ? nil : String(trimmedIcon.prefix(1))

            let label = try ManageLabelsUseCase.createLabel(
                named: editorName,
                color: editorColor,
                icon: iconValue,
                groupID: editorGroupID,
                using: modelContext
            )
            isCreatingLabel = false
            selectedLabelIDs = [label.id]
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func autoSave() {
        guard !suppressAutoSave else { return }
        applyChanges()
    }

    private func applyChanges() {
        guard let label = singleSelectedLabel else { return }
        guard !editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let trimmedIcon = editorIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            let iconValue = trimmedIcon.isEmpty ? nil : String(trimmedIcon.prefix(1))

            try ManageLabelsUseCase.update(
                label,
                name: editorName,
                color: editorColor,
                icon: iconValue,
                groupID: editorGroupID,
                using: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bulkMoveToGroup() {
        do {
            for id in selectedLabelIDs {
                if let label = coordinator.allLabels.first(where: { $0.id == id }) {
                    try ManageLabelsUseCase.assignToGroup(label, groupID: bulkGroupID, using: modelContext)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createGroup() {
        do {
            try ManageLabelGroupsUseCase.create(named: newGroupName, using: modelContext)
            newGroupName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitGroupRename(_ group: LabelGroup) {
        do {
            try ManageLabelGroupsUseCase.rename(group, to: renamingGroupName, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
        renamingGroupID = nil
        renamingGroupName = ""
    }

    private func cancelGroupRename() {
        renamingGroupID = nil
        renamingGroupName = ""
    }

    // MARK: - Deletion

    private var deletionDialogTitle: String {
        guard let target = deletionTarget else { return "Delete" }
        switch target {
        case .labels(let ids):
            return ids.count == 1 ? "Delete Label" : "Delete \(ids.count) Labels"
        case .group(let group):
            return "Delete Group \"\(group.name)\""
        }
    }

    private var deletionDialogMessage: String {
        guard let target = deletionTarget else { return "" }
        switch target {
        case .labels(let ids):
            let count = ids.count
            let affectedDocs = coordinator.allLabels
                .filter { ids.contains($0.id) }
                .reduce(into: Set<UUID>()) { result, label in
                    for doc in label.documents { result.insert(doc.id) }
                }
            if affectedDocs.isEmpty {
                return count == 1
                    ? "This label has no documents assigned."
                    : "These labels have no documents assigned."
            }
            return count == 1
                ? "This will remove the label from \(affectedDocs.count) document(s). Documents themselves are kept."
                : "This will remove these labels from \(affectedDocs.count) document(s). Documents themselves are kept."
        case .group:
            return "Labels in this group will become ungrouped. No labels or documents are deleted."
        }
    }

    private func performDeletion() {
        guard let target = deletionTarget else { return }
        do {
            switch target {
            case .labels(let ids):
                for id in ids {
                    if let label = coordinator.allLabels.first(where: { $0.id == id }) {
                        try ManageLabelsUseCase.delete(label, using: modelContext)
                    }
                }
                selectedLabelIDs.subtract(ids)
            case .group(let group):
                try ManageLabelGroupsUseCase.delete(group, using: modelContext)
            }
            deletionTarget = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
