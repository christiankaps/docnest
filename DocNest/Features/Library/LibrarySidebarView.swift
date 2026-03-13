import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case allDocuments = "All Documents"
    case recent = "Recent Imports"
    case needsLabels = "Needs Labels"
    case bin = "Bin"

    var id: String { rawValue }
}

struct LibrarySidebarView: View {
    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingLabel = false
    @State private var newLabelName = ""
    @State private var newLabelColor: LabelColor = .blue
    @State private var editingLabelID: PersistentIdentifier?
    @State private var editedLabelName = ""
    @State private var errorMessage: String?
    @State private var pendingLabelDeletion: PendingLabelDeletion?

    private var sortedLabels: [LabelTag] {
        coordinator.allLabels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        @Bindable var coordinator = coordinator

        List {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        coordinator.selectedSection = section
                        if section == .needsLabels {
                            coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                        }
                    } label: {
                        HStack {
                            Label(section.rawValue, systemImage: iconName(for: section))
                            Spacer()
                            Text("\(coordinator.sidebarCounts.count(for: section))")
                                .font(AppTypography.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if coordinator.selectedSection == section {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .dropDestination(for: String.self) { items, _ in
                        guard section == .bin else {
                            return false
                        }

                        return coordinator.handleDroppedDocumentIDs(items)
                    }
                }

                if coordinator.selectedSection == .bin {
                    HStack(spacing: 8) {
                        Button("Restore All") {
                            coordinator.restoreAllFromBin()
                        }
                        .disabled(coordinator.trashedDocuments.isEmpty)

                        Button("Remove All", role: .destructive) {
                            coordinator.isConfirmingBinRemoval = true
                        }
                        .disabled(coordinator.trashedDocuments.isEmpty)
                    }
                    .font(AppTypography.caption)
                }
            }

            Section("Label Filters") {
                HStack {
                    Button("Clear Label Filters") {
                        coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                    }
                    .disabled(coordinator.labelFilterSelection.visualSelection.isEmpty)

                    Spacer()

                    Button {
                        isAddingLabel = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Label")
                }

                if isAddingLabel {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("New label", text: $newLabelName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addLabel)

                            Menu {
                                ForEach(LabelColor.allCases) { color in
                                    Button {
                                        newLabelColor = color
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(color.color)
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                            Text(color.displayName)
                                            if newLabelColor == color {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(newLabelColor.color)
                                        .frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                    Text(newLabelColor.displayName)
                                        .font(AppTypography.caption)
                                }
                                .foregroundStyle(.primary)
                            }
                            .help("Choose label color")

                            Button("Add", action: addLabel)
                                .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if coordinator.allLabels.isEmpty {
                    Text("No labels yet")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedLabels) { label in
                        if editingLabelID == label.persistentModelID {
                            TextField("Label name", text: $editedLabelName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    renameLabel(label)
                                }
                        } else {
                            Button {
                                toggleLabelSelection(label)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(label.labelColor.color)
                                        .frame(width: 10, height: 10)
                                    Text(label.name)
                                    Spacer()
                                    Text("\(coordinator.sidebarCounts.count(for: label))")
                                        .font(AppTypography.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if coordinator.labelFilterSelection.visualSelection.contains(label.persistentModelID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onDrag {
                                NSItemProvider(
                                    item: DocumentLabelDragPayload.payload(for: label.id) as NSString,
                                    typeIdentifier: UTType.plainText.identifier
                                )
                            }
                            .dropDestination(for: String.self) { items, _ in
                                coordinator.handleDroppedDocumentsOnLabel(items, label: label)
                            }
                            .contextMenu {
                                Button("Rename") {
                                    beginEditing(label)
                                }

                                Menu("Color") {
                                    ForEach(LabelColor.allCases) { color in
                                        Button {
                                            changeColor(of: label, to: color)
                                        } label: {
                                            HStack {
                                                Text(color.displayName)
                                                if label.labelColor == color {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }

                                Button("Delete", role: .destructive) {
                                    deleteLabel(label)
                                }
                            }
                            .onTapGesture(count: 2) {
                                beginEditing(label)
                            }
                        }
                    }
                    .onMove(perform: moveLabels)
                }
            }
        }
        .navigationTitle("Library")
        .confirmationDialog(
            pendingLabelDeletion?.title ?? "Delete Label",
            isPresented: pendingLabelDeletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Label", role: .destructive) {
                confirmDeleteLabel()
            }

            Button("Cancel", role: .cancel) {
                pendingLabelDeletion = nil
            }
        } message: {
            Text(pendingLabelDeletion?.message ?? "")
        }
        .alert("Label Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown label error.")
        }

    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private var pendingLabelDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingLabelDeletion != nil },
            set: { newValue in
                if !newValue {
                    pendingLabelDeletion = nil
                }
            }
        )
    }

    private func toggleLabelSelection(_ label: LabelTag) {
        coordinator.labelFilterSelection.toggleVisualSelection(for: label.persistentModelID)
    }

    private func addLabel() {
        do {
            _ = try ManageLabelsUseCase.createLabel(named: newLabelName, color: newLabelColor, using: modelContext)
            newLabelName = ""
            newLabelColor = .blue
            isAddingLabel = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ label: LabelTag) {
        editingLabelID = label.persistentModelID
        editedLabelName = label.name
    }

    private func renameLabel(_ label: LabelTag) {
        do {
            _ = try ManageLabelsUseCase.rename(label, to: editedLabelName, using: modelContext)
            editingLabelID = nil
            editedLabelName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeColor(of label: LabelTag, to color: LabelColor) {
        do {
            try ManageLabelsUseCase.changeColor(of: label, to: color, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteLabel(_ label: LabelTag) {
        let pendingDeletion = PendingLabelDeletion(label: label)

        if pendingDeletion.requiresConfirmation {
            pendingLabelDeletion = pendingDeletion
            return
        }

        do {
            try performDeleteLabel(label)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDeleteLabel() {
        guard let pendingLabelDeletion else {
            return
        }

        do {
            try performDeleteLabel(pendingLabelDeletion.label)
            self.pendingLabelDeletion = nil
        } catch {
            self.pendingLabelDeletion = nil
            errorMessage = error.localizedDescription
        }
    }

    private func performDeleteLabel(_ label: LabelTag) throws {
        try ManageLabelsUseCase.delete(label, using: modelContext)
    }

    private func moveLabels(from source: IndexSet, to destination: Int) {
        do {
            try ManageLabelsUseCase.reorderLabels(from: source, to: destination, labels: sortedLabels, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func iconName(for section: LibrarySection) -> String {
        switch section {
        case .allDocuments:
            "doc.richtext"
        case .recent:
            "clock"
        case .needsLabels:
            "tag.slash"
        case .bin:
            "trash"
        }
    }

}

struct PendingLabelDeletion {
    let label: LabelTag
    let affectedDocumentCount: Int

    init(label: LabelTag) {
        self.label = label
        affectedDocumentCount = Set(label.documents.map(\.persistentModelID)).count
    }

    var title: String {
        "Delete Label"
    }

    var requiresConfirmation: Bool {
        affectedDocumentCount > 0
    }

    var message: String {
        if affectedDocumentCount == 1 {
            return "Deleting \"\(label.name)\" will remove this label from 1 document. The document itself will be kept."
        }

        return "Deleting \"\(label.name)\" will remove this label from \(affectedDocumentCount) documents. The documents themselves will be kept."
    }
}

struct LibrarySidebarCounts {
    private let sectionCounts: [LibrarySection: Int]
    private let labelCounts: [PersistentIdentifier: Int]

    init(documents: [DocumentRecord], labels: [LabelTag], recentLimit: Int) {
        let activeDocuments = documents.filter { $0.trashedAt == nil }
        let trashedDocuments = documents.filter { $0.trashedAt != nil }
        var needsLabelsCount = 0
        var computedLabelCounts = Dictionary(uniqueKeysWithValues: labels.map { ($0.persistentModelID, 0) })

        for document in activeDocuments {
            if document.labels.isEmpty {
                needsLabelsCount += 1
            }

            for labelID in Set(document.labels.map(\.persistentModelID)) {
                computedLabelCounts[labelID, default: 0] += 1
            }
        }

        sectionCounts = [
            .allDocuments: activeDocuments.count,
            .recent: min(activeDocuments.count, recentLimit),
            .needsLabels: needsLabelsCount,
            .bin: trashedDocuments.count
        ]
        labelCounts = computedLabelCounts
    }

    func count(for section: LibrarySection) -> Int {
        sectionCounts[section, default: 0]
    }

    func count(for label: LabelTag) -> Int {
        labelCounts[label.persistentModelID, default: 0]
    }
}

#Preview {
    LibrarySidebarView()
        .environment(LibraryCoordinator())
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
