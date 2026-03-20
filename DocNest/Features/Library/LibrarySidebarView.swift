import SwiftUI
import SwiftData
import OSLog

enum LibrarySection: String, CaseIterable, Identifiable {
    case allDocuments = "All Documents"
    case recent = "Recent Imports"
    case needsLabels = "Needs Labels"
    case bin = "Bin"

    var id: String { rawValue }
}

private enum ReorderInsertionEdge {
    case above(PersistentIdentifier)
    case below(PersistentIdentifier)
}

struct LibrarySidebarView: View {
    private static let performanceLogger = Logger(subsystem: "com.kaps.docnest", category: "performance")

    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingLabel = false
    @State private var newLabelName = ""
    @State private var newLabelColor: LabelColor = .blue
    @State private var newLabelIcon = ""
    @State private var editingLabelID: PersistentIdentifier?
    @State private var editedLabelName = ""
    @State private var editedLabelColor: LabelColor = .blue
    @State private var editedLabelIcon = ""
    @State private var errorMessage: String?
    @State private var pendingLabelDeletion: PendingLabelDeletion?
    @State private var hoveredLabelDropTargetID: PersistentIdentifier?
    @State private var draggingLabelID: UUID?
    @State private var reorderInsertionEdge: ReorderInsertionEdge?
    @State private var smartFolderEditorConfig: SmartFolderEditorConfig?
    @State private var draggingSmartFolderID: UUID?
    @State private var smartFolderReorderInsertionEdge: ReorderInsertionEdge?

    private var sortedLabels: [LabelTag] {
        coordinator.allLabels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        #if DEBUG
        let renderStartTime = Date().timeIntervalSinceReferenceDate
        #endif

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                librarySectionContent

                smartFolderSection

                labelSectionContent
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(coordinator.libraryURL?.deletingPathExtension().lastPathComponent ?? "DocNest")
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
        .sheet(item: $smartFolderEditorConfig) { config in
            SmartFolderEditorSheet(
                config: config,
                allLabels: coordinator.allLabels
            )
        }

        #if DEBUG
        .onAppear {
            debugLogSidebarRenderTiming(startTime: renderStartTime, coordinator: coordinator)
        }
        #endif

    }

    @ViewBuilder
    private var librarySectionContent: some View {
        sidebarSection("Library") {
            ForEach(LibrarySection.allCases) { section in
                Button {
                    coordinator.sidebarSelection = .section(section)
                    if section == .needsLabels {
                        coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                    }
                } label: {
                    LibrarySectionRowView(
                        title: section.rawValue,
                        systemImage: iconName(for: section),
                        count: coordinator.sidebarCounts.count(for: section),
                        isSelected: coordinator.sidebarSelection == .section(section)
                    )
                }
                .buttonStyle(.plain)
                .sidebarRow()
                .dropDestination(for: String.self) { items, _ in
                    guard section == .bin else {
                        return false
                    }

                    return coordinator.handleDroppedDocumentIDs(items)
                }
            }

            if coordinator.sidebarSelection == .section(.bin) {
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
                .sidebarRow()
            }
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            content()
        }
    }

    private func labelSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 10, weight: .semibold))
                Text("Labels")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)

                Spacer()

                if !coordinator.labelFilterSelection.visualSelection.isEmpty && coordinator.selectedSmartFolderID == nil {
                    Button {
                        coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear label filters")
                }

                Button {
                    isAddingLabel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add Label")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            content()
        }
    }

    @ViewBuilder
    private var labelSectionContent: some View {
        labelSection {
            if isAddingLabel {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        EmojiPickerButton(selection: $newLabelIcon)
                            .frame(width: 28, height: 22)
                            .help("Choose emoji icon (optional)")

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
                .sidebarRow()
            }

            if coordinator.allLabels.isEmpty {
                Text("No labels yet")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .sidebarRow()
            } else {
                ForEach(sortedLabels) { label in
                    if editingLabelID == label.persistentModelID {
                        labelEditRow(for: label)
                    } else {
                        labelDisplayRow(for: label)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func labelEditRow(for label: LabelTag) -> some View {
        HStack(spacing: 8) {
            EmojiPickerButton(selection: $editedLabelIcon)
                .frame(width: 28, height: 22)
                .help("Choose emoji icon (optional)")

            TextField("Label name", text: $editedLabelName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitEdit(label) }

            Menu {
                ForEach(LabelColor.allCases) { color in
                    Button {
                        editedLabelColor = color
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color.color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                            Text(color.displayName)
                            if editedLabelColor == color {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(editedLabelColor.color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    Text(editedLabelColor.displayName)
                        .font(AppTypography.caption)
                }
                .foregroundStyle(.primary)
            }

            Button("Save") { commitEdit(label) }
                .disabled(editedLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sidebarRow()
    }

    @ViewBuilder
    private func labelDisplayRow(for label: LabelTag) -> some View {
        let isDocumentDrop = hoveredLabelDropTargetID == label.persistentModelID && draggingLabelID == nil
        let showAboveLine = reorderInsertionEdge.flatMap { edge in
            if case .above(let id) = edge, id == label.persistentModelID { return true }
            return nil
        } ?? false
        let showBelowLine = reorderInsertionEdge.flatMap { edge in
            if case .below(let id) = edge, id == label.persistentModelID { return true }
            return nil
        } ?? false

        LibraryLabelRowView(
            name: label.name,
            color: label.labelColor.color,
            icon: label.icon,
            count: coordinator.sidebarCounts.count(for: label),
            isSelected: coordinator.effectiveHighlightedLabelIDs.contains(label.persistentModelID)
        )
        .sidebarRow()
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isDocumentDrop ? 0.16 : 0))
        )
        .overlay(alignment: .top) {
            if showAboveLine {
                ReorderInsertionLine()
                    .offset(y: -1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if showBelowLine {
                ReorderInsertionLine()
                    .offset(y: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if coordinator.selectedSmartFolderID != nil {
                // Transition from smart folder to interactive label filtering:
                // seed the filter with the folder's labels, then toggle the clicked one.
                let currentHighlighted = coordinator.effectiveHighlightedLabelIDs
                coordinator.sidebarSelection = .section(.allDocuments)
                coordinator.labelFilterSelection.replaceVisualSelection(with: currentHighlighted)
            }
            toggleLabelSelection(label)
        }
        .draggable(DocumentLabelDragPayload.payload(for: label.id)) {
            LabelDragPreview(name: label.name, color: label.labelColor.color, icon: label.icon)
                .onAppear { draggingLabelID = label.id }
        }
        .dropDestination(for: String.self) { items, _ in
            draggingLabelID = nil
            reorderInsertionEdge = nil
            return handleDroppedStrings(items, onto: label)
        } isTargeted: { isTargeted in
            if isTargeted {
                hoveredLabelDropTargetID = label.persistentModelID
                updateReorderInsertionEdge(for: label)
            } else if hoveredLabelDropTargetID == label.persistentModelID {
                hoveredLabelDropTargetID = nil
                reorderInsertionEdge = nil
            }
        }
        .accessibilityHint("Drop documents here to assign the \(label.name) label")
        .contextMenu {
            Button("Edit") {
                beginEditing(label)
            }

            Button("Delete", role: .destructive) {
                deleteLabel(label)
            }
        }
        .onTapGesture(count: 2) {
            beginEditing(label)
        }
    }

    @ViewBuilder
    private var smartFolderSection: some View {
        let folders = coordinator.allSmartFolders
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 10, weight: .semibold))
                Text("Smart Folders")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)

                Spacer()

                Button {
                    smartFolderEditorConfig = SmartFolderEditorConfig(
                        mode: .create,
                        prefillLabelIDs: coordinator.prefillLabelIDsForNewSmartFolder()
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add Smart Folder")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if folders.isEmpty {
                Text("No smart folders yet")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .sidebarRow()
            } else {
                ForEach(folders) { folder in
                    let isSelected = coordinator.sidebarSelection == .smartFolder(folder.persistentModelID)
                        || coordinator.labelFilterMatchesSmartFolder(folder)
                    let showAboveLine = smartFolderReorderInsertionEdge.flatMap { edge in
                        if case .above(let id) = edge, id == folder.persistentModelID { return true }
                        return nil
                    } ?? false
                    let showBelowLine = smartFolderReorderInsertionEdge.flatMap { edge in
                        if case .below(let id) = edge, id == folder.persistentModelID { return true }
                        return nil
                    } ?? false

                    SmartFolderRowView(
                        name: folder.name,
                        icon: folder.icon,
                        count: coordinator.smartFolderCounts[folder.persistentModelID] ?? 0,
                        isSelected: isSelected
                    )
                    .sidebarRow()
                    .overlay(alignment: .top) {
                        if showAboveLine {
                            ReorderInsertionLine()
                                .offset(y: -1.5)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if showBelowLine {
                            ReorderInsertionLine()
                                .offset(y: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if coordinator.sidebarSelection == .smartFolder(folder.persistentModelID) {
                            coordinator.sidebarSelection = .section(.allDocuments)
                            coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                            coordinator.searchText = ""
                        } else {
                            coordinator.sidebarSelection = .smartFolder(folder.persistentModelID)
                        }
                    }
                    .draggable(SmartFolderDragPayload.payload(for: folder.id)) {
                        SmartFolderDragPreview(name: folder.name, icon: folder.icon)
                            .onAppear { draggingSmartFolderID = folder.id }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        draggingSmartFolderID = nil
                        smartFolderReorderInsertionEdge = nil
                        return handleSmartFolderDrop(items, onto: folder)
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            updateSmartFolderReorderInsertionEdge(for: folder)
                        } else if smartFolderReorderInsertionEdge != nil {
                            smartFolderReorderInsertionEdge = nil
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            smartFolderEditorConfig = SmartFolderEditorConfig(
                                mode: .edit(folder),
                                prefillLabelIDs: folder.labelIDs
                            )
                        }
                        Button("Delete", role: .destructive) {
                            deleteSmartFolder(folder)
                        }
                    }
                }
            }
        }
    }

    private func updateSmartFolderReorderInsertionEdge(for target: SmartFolder) {
        guard let draggingSmartFolderID else {
            smartFolderReorderInsertionEdge = nil
            return
        }

        let folders = coordinator.allSmartFolders
        guard let sourceIndex = folders.firstIndex(where: { $0.id == draggingSmartFolderID }),
              let targetIndex = folders.firstIndex(where: { $0.persistentModelID == target.persistentModelID }),
              sourceIndex != targetIndex else {
            smartFolderReorderInsertionEdge = nil
            return
        }

        let targetID = target.persistentModelID
        if sourceIndex < targetIndex {
            smartFolderReorderInsertionEdge = .below(targetID)
        } else {
            smartFolderReorderInsertionEdge = .above(targetID)
        }
    }

    private func handleSmartFolderDrop(_ items: [String], onto target: SmartFolder) -> Bool {
        guard let payload = items.first else { return false }

        // Smart folder reorder
        if let sourceID = SmartFolderDragPayload.folderID(from: payload) {
            let folders = coordinator.allSmartFolders
            guard let sourceIndex = folders.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = folders.firstIndex(where: { $0.persistentModelID == target.persistentModelID }),
                  sourceIndex != targetIndex else {
                return false
            }

            let source = IndexSet(integer: sourceIndex)
            let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex

            do {
                try ManageSmartFoldersUseCase.reorder(from: source, to: destination, folders: folders, using: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            return true
        }

        // Document drop — assign the smart folder's labels to the dropped documents
        return coordinator.assignSmartFolderLabels(target, toDroppedPayload: items)
    }

    private func deleteSmartFolder(_ folder: SmartFolder) {
        let wasSelected = coordinator.sidebarSelection == .smartFolder(folder.persistentModelID)
        do {
            try ManageSmartFoldersUseCase.delete(folder, using: modelContext)
            if wasSelected {
                coordinator.sidebarSelection = .section(.allDocuments)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func debugLogSidebarRenderTiming(startTime: TimeInterval, coordinator: LibraryCoordinator) {
        #if DEBUG
        let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
        Self.performanceLogger.log(
            "[Performance][SidebarRender] selection=\(coordinator.selectedSection?.rawValue ?? "smartFolder", privacy: .public) labels=\(coordinator.allLabels.count) visualFilters=\(coordinator.labelFilterSelection.visualSelection.count) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
        )
        #endif
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
        let icon = newLabelIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try ManageLabelsUseCase.createLabel(named: newLabelName, color: newLabelColor, icon: icon.isEmpty ? nil : String(icon.prefix(1)), using: modelContext)
            newLabelName = ""
            newLabelColor = .blue
            newLabelIcon = ""
            isAddingLabel = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ label: LabelTag) {
        editingLabelID = label.persistentModelID
        editedLabelName = label.name
        editedLabelColor = label.labelColor
        editedLabelIcon = label.icon ?? ""
    }

    private func commitEdit(_ label: LabelTag) {
        do {
            _ = try ManageLabelsUseCase.rename(label, to: editedLabelName, using: modelContext)
            try ManageLabelsUseCase.changeColor(of: label, to: editedLabelColor, using: modelContext)
            let iconTrimmed = editedLabelIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            try ManageLabelsUseCase.changeIcon(of: label, to: iconTrimmed.isEmpty ? nil : String(iconTrimmed.prefix(1)), using: modelContext)
            editingLabelID = nil
            editedLabelName = ""
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

    private func updateReorderInsertionEdge(for targetLabel: LabelTag) {
        guard let draggingLabelID else {
            reorderInsertionEdge = nil
            return
        }

        let labels = sortedLabels
        guard let sourceIndex = labels.firstIndex(where: { $0.id == draggingLabelID }),
              let targetIndex = labels.firstIndex(where: { $0.persistentModelID == targetLabel.persistentModelID }),
              sourceIndex != targetIndex else {
            reorderInsertionEdge = nil
            return
        }

        let targetID = targetLabel.persistentModelID
        if sourceIndex < targetIndex {
            reorderInsertionEdge = .below(targetID)
        } else {
            reorderInsertionEdge = .above(targetID)
        }
    }

    private func handleDroppedStrings(_ items: [String], onto label: LabelTag) -> Bool {
        guard !items.isEmpty else { return false }

        // A label-label drag is a reorder operation; document drags are assignments.
        if let payload = items.first,
           let sourceLabelID = DocumentLabelDragPayload.labelID(from: payload) {
            reorderLabel(sourceID: sourceLabelID, onto: label)
            return true
        }

        return coordinator.handleDroppedDocumentsOnLabel(items, label: label)
    }

    private func reorderLabel(sourceID: UUID, onto targetLabel: LabelTag) {
        let labels = sortedLabels
        guard let sourceIndex = labels.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = labels.firstIndex(where: { $0.persistentModelID == targetLabel.persistentModelID }),
              sourceIndex != targetIndex else { return }

        let source = IndexSet(integer: sourceIndex)
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex

        do {
            try ManageLabelsUseCase.reorderLabels(from: source, to: destination, labels: labels, using: modelContext)
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

private extension View {
    func sidebarRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibrarySectionRowView: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.30 : (isHovered ? 0.06 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct LibraryLabelRowView: View {
    let name: String
    let color: Color
    var icon: String? = nil
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 12))
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
            }
            Text(name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(isSelected ? 0.30 : (isHovered ? 0.08 : 0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(color.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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

    init(
        activeDocuments: [DocumentRecord],
        trashedCount: Int,
        labels: [LabelTag],
        recentLimit: Int,
        labelSourceDocuments: [DocumentRecord],
        activeLabelFilterIDs: Set<PersistentIdentifier>
    ) {
        var needsLabelsCount = 0

        for document in activeDocuments {
            if document.labels.isEmpty {
                needsLabelsCount += 1
            }
        }

        sectionCounts = [
            .allDocuments: activeDocuments.count,
            .recent: min(activeDocuments.count, recentLimit),
            .needsLabels: needsLabelsCount,
            .bin: trashedCount
        ]

        var computedLabelCounts = Dictionary(uniqueKeysWithValues: labels.map { ($0.persistentModelID, 0) })
        for document in labelSourceDocuments {
            let documentLabelIDs = Set(document.labels.map(\.persistentModelID))

            // Only count if the document matches all other active label filters
            let matchesOtherFilters = activeLabelFilterIDs.allSatisfy { documentLabelIDs.contains($0) }
            guard matchesOtherFilters else { continue }

            for labelID in documentLabelIDs {
                computedLabelCounts[labelID, default: 0] += 1
            }
        }
        labelCounts = computedLabelCounts
    }

    func count(for section: LibrarySection) -> Int {
        sectionCounts[section, default: 0]
    }

    func count(for label: LabelTag) -> Int {
        labelCounts[label.persistentModelID, default: 0]
    }
}

private struct ReorderInsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 12)
        .allowsHitTesting(false)
    }
}

private struct LabelDragPreview: View {
    let name: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.callout)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(name)
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct EmojiPickerButton: NSViewRepresentable {
    @Binding var selection: String

    func makeNSView(context: Context) -> EmojiInputView {
        let view = EmojiInputView()
        view.emoji = selection
        view.onEmojiChanged = { emoji in
            context.coordinator.selection = emoji
        }
        return view
    }

    func updateNSView(_ nsView: EmojiInputView, context: Context) {
        nsView.emoji = selection
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator {
        @Binding var selection: String

        init(selection: Binding<String>) {
            _selection = selection
        }
    }
}

final class EmojiInputView: NSView, NSTextInputClient {
    var emoji = ""
    var onEmojiChanged: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSApp.orderFrontCharacterPalette(nil)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let str: NSAttributedString
        if emoji.isEmpty {
            if let img = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                let configured = img.withSymbolConfiguration(config) ?? img
                configured.draw(in: CGRect(
                    x: (bounds.width - 16) / 2,
                    y: (bounds.height - 16) / 2,
                    width: 16,
                    height: 16
                ))
            }
            return
        } else {
            str = NSAttributedString(string: emoji, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
            ])
        }
        let size = str.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        str.draw(at: point)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? String(describing: string)
        guard !text.isEmpty else { return }
        let first = String(text.prefix(1))
        emoji = first
        onEmojiChanged?(first)
        needsDisplay = true
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }
    func characterIndex(for point: NSPoint) -> Int { 0 }
}

private struct SmartFolderRowView: View {
    let name: String
    let icon: String?
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 12))
            } else {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
            }
            Text(name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.30 : (isHovered ? 0.06 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct SmartFolderDragPreview: View {
    let name: String
    let icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.callout)
            } else {
                Image(systemName: "folder.badge.gearshape")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            Text(name)
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

enum SmartFolderDragPayload {
    private static let prefix = "smartfolder:"

    static func payload(for folderID: UUID) -> String {
        "\(prefix)\(folderID.uuidString)"
    }

    static func folderID(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

struct SmartFolderEditorConfig: Identifiable {
    let id = UUID()
    let mode: Mode
    let prefillLabelIDs: [UUID]

    enum Mode {
        case create
        case edit(SmartFolder)
    }
}

#Preview {
    LibrarySidebarView()
        .environment(LibraryCoordinator())
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}



