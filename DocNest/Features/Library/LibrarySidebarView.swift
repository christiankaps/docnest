import AppKit
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

    @State private var errorMessage: String?
    @State private var pendingLabelDeletion: PendingLabelDeletion?
    @State private var hoveredLabelDropTargetID: PersistentIdentifier?
    @State private var draggingLabelID: UUID?
    @State private var reorderInsertionEdge: ReorderInsertionEdge?
    @State private var smartFolderEditorConfig: SmartFolderEditorConfig?
    @State private var draggingSmartFolderID: UUID?
    @State private var smartFolderReorderInsertionEdge: ReorderInsertionEdge?
    @State private var labelEditorConfig: LabelEditorConfig?
    @State private var collapsedGroupIDs: Set<UUID> = []
    @State private var newGroupName = ""
    @State private var isShowingNewGroupAlert = false
    @State private var renamingGroupID: UUID?
    @State private var renamingGroupName = ""

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
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background {
            ZStack {
                SidebarBlurBackground()
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.20))
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 0.5)
            }
        }
        .navigationTitle(coordinator.libraryPackageURL?.deletingPathExtension().lastPathComponent ?? "DocNest")
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
        .sheet(item: $labelEditorConfig) { config in
            LabelEditorSheet(
                config: config,
                allGroups: coordinator.allLabelGroups
            )
        }
        .alert("New Group", isPresented: $isShowingNewGroupAlert) {
            TextField("Group name", text: $newGroupName)
            Button("Create") { createNewGroup() }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Enter a name for the label group.")
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
            SidebarSectionHeader(title: title)
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 4)

            content()
        }
    }

    private func labelSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Label("Labels", systemImage: "tag")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer()

                if !coordinator.labelFilterSelection.visualSelection.isEmpty && coordinator.selectedSmartFolderID == nil {
                    Button {
                        coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear label filters")
                }

                Button {
                    labelEditorConfig = LabelEditorConfig(mode: .create(groupID: nil))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Add Label")

                Button {
                    isShowingNewGroupAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Add Label Group")
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)

            content()
        }
    }

    @ViewBuilder
    private var labelSectionContent: some View {
        labelSection {
            // Ungrouped labels
            ForEach(ungroupedLabels) { label in
                labelDisplayRow(for: label)
            }

            // Grouped labels
            ForEach(sortedGroups) { group in
                labelGroupHeader(for: group)

                if !collapsedGroupIDs.contains(group.id) {
                    ForEach(labelsInGroup(group)) { label in
                        labelDisplayRow(for: label)
                            .padding(.leading, 12)
                    }
                }
            }

            if coordinator.allLabels.isEmpty && coordinator.allLabelGroups.isEmpty {
                Text("No labels yet")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .sidebarRow()
            }
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

    @ViewBuilder
    private func labelGroupHeader(for group: LabelGroup) -> some View {
        let isCollapsed = collapsedGroupIDs.contains(group.id)
        let groupLabels = labelsInGroup(group)
        let isRenaming = renamingGroupID == group.id

        if isRenaming {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                TextField("Group name", text: $renamingGroupName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { commitGroupRename(group) }

                Button("Save") { commitGroupRename(group) }
                    .font(.caption)
                    .disabled(renamingGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    renamingGroupID = nil
                    renamingGroupName = ""
                }
                .font(.caption)
            }
            .sidebarRow()
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedGroupIDs.remove(group.id)
                    } else {
                        collapsedGroupIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(group.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(groupLabels.count)")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .sidebarRow()
            .dropDestination(for: String.self) { items, _ in
                handleLabelDropOntoGroup(items, group: group)
            }
            .contextMenu {
                Button("Rename Group") {
                    renamingGroupID = group.id
                    renamingGroupName = group.name
                }
                Button("Add Label to Group") {
                    labelEditorConfig = LabelEditorConfig(mode: .create(groupID: group.id))
                }
                Divider()
                Button("Delete Group", role: .destructive) {
                    deleteGroup(group)
                }
            }
        }
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
            isSelected: coordinator.effectiveHighlightedLabelIDs.contains(label.persistentModelID),
            dragPayload: DocumentLabelDragPayload.payload(for: label.id),
            dragPreview: AnyView(
                LabelDragPreview(name: label.name, color: label.labelColor.color, icon: label.icon)
                    .onAppear { draggingLabelID = label.id }
            )
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
                labelEditorConfig = LabelEditorConfig(mode: .edit(label))
            }

            if label.groupID != nil {
                Button("Remove from Group") {
                    removeFromGroup(label)
                }
            }

            Button("Delete", role: .destructive) {
                deleteLabel(label)
            }
        }
    }

    @ViewBuilder
    private var smartFolderSection: some View {
        let folders = coordinator.allSmartFolders
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 12, weight: .semibold))
                Text("Smart Folders")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    smartFolderEditorConfig = SmartFolderEditorConfig(
                        mode: .create,
                        prefillLabelIDs: coordinator.prefillLabelIDsForNewSmartFolder()
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Add Smart Folder")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 8)
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
                        isSelected: isSelected,
                        dragPayload: SmartFolderDragPayload.payload(for: folder.id),
                        dragPreview: AnyView(
                            SmartFolderDragPreview(name: folder.name, icon: folder.icon)
                                .onAppear { draggingSmartFolderID = folder.id }
                        )
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

    private func createNewGroup() {
        guard !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            newGroupName = ""
            return
        }
        do {
            _ = try ManageLabelGroupsUseCase.create(named: newGroupName, using: modelContext)
            newGroupName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitGroupRename(_ group: LabelGroup) {
        do {
            try ManageLabelGroupsUseCase.rename(group, to: renamingGroupName, using: modelContext)
            renamingGroupID = nil
            renamingGroupName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGroup(_ group: LabelGroup) {
        do {
            try ManageLabelGroupsUseCase.delete(group, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFromGroup(_ label: LabelTag) {
        do {
            try ManageLabelsUseCase.assignToGroup(label, groupID: nil, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleLabelDropOntoGroup(_ items: [String], group: LabelGroup) -> Bool {
        guard let payload = items.first,
              let sourceLabelID = DocumentLabelDragPayload.labelID(from: payload),
              let sourceLabel = sortedLabels.first(where: { $0.id == sourceLabelID }) else {
            return false
        }

        do {
            try ManageLabelsUseCase.assignToGroup(sourceLabel, groupID: group.id, using: modelContext)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        guard let sourceLabel = sortedLabels.first(where: { $0.id == sourceID }) else { return }

        let targetGroupID = targetLabel.groupID

        // If moving between groups, update groupID first
        if sourceLabel.groupID != targetGroupID {
            do {
                try ManageLabelsUseCase.assignToGroup(sourceLabel, groupID: targetGroupID, using: modelContext)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        // Reorder within the target scope (same group or ungrouped)
        let labelsInScope = sortedLabels.filter { $0.groupID == targetGroupID }
        guard let sourceIndex = labelsInScope.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = labelsInScope.firstIndex(where: { $0.persistentModelID == targetLabel.persistentModelID }),
              sourceIndex != targetIndex else { return }

        let source = IndexSet(integer: sourceIndex)
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex

        do {
            try ManageLabelsUseCase.reorderLabels(from: source, to: destination, labels: labelsInScope, using: modelContext)
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

private struct SidebarBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = false
    }
}

private extension View {
    func sidebarRow() -> some View {
        self
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct LibrarySectionRowView: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(AppTypography.body.weight(isSelected ? .semibold : .regular))
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.65))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(0.20)
                    : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
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
    let dragPayload: String
    let dragPreview: AnyView

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 12))
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(color.opacity(isSelected ? 0.95 : 0.85))
            }
            Text(name)
                .font(AppTypography.body.weight(isSelected ? .semibold : .regular))
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.65))
            dragHandle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                    ? color.opacity(0.20)
                    : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isHovered ? .secondary : .tertiary)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .draggable(dragPayload) { dragPreview }
            .help("Drag label")
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
    private var isPresentingPalette = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isPresentingPalette else { return }
        isPresentingPalette = true
        window?.makeFirstResponder(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            NSApp.orderFrontCharacterPalette(nil)
            self.isPresentingPalette = false
        }
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
    let dragPayload: String
    let dragPreview: AnyView

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
                .font(AppTypography.body.weight(isSelected ? .semibold : .regular))
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.65))
            dragHandle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(0.20)
                    : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isHovered ? .secondary : .tertiary)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .draggable(dragPayload) { dragPreview }
            .help("Drag smart folder")
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
