import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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
    @State private var editingIconLabelID: PersistentIdentifier?
    @State private var editedIcon = ""
    @State private var errorMessage: String?
    @State private var pendingLabelDeletion: PendingLabelDeletion?
    @State private var hoveredLabelDropTargetID: PersistentIdentifier?
    @State private var draggingLabelID: UUID?
    @State private var reorderInsertionEdge: ReorderInsertionEdge?

    private var sortedLabels: [LabelTag] {
        coordinator.allLabels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        let renderStartTime = Date().timeIntervalSinceReferenceDate
        let labels = sortedLabels
        @Bindable var coordinator = coordinator

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarSection("Library") {
                    ForEach(LibrarySection.allCases) { section in
                        Button {
                            coordinator.selectedSection = section
                            if section == .needsLabels {
                                coordinator.labelFilterSelection.replaceVisualSelection(with: [])
                            }
                        } label: {
                            LibrarySectionRowView(
                                title: section.rawValue,
                                systemImage: iconName(for: section),
                                count: coordinator.sidebarCounts.count(for: section),
                                isSelected: coordinator.selectedSection == section
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
                        .sidebarRow()
                    }
                }

                sidebarSection("Label Filters") {
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
                    .sidebarRow()

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
                        ForEach(labels) { label in
                            if editingLabelID == label.persistentModelID {
                                TextField("Label name", text: $editedLabelName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        renameLabel(label)
                                    }
                                    .sidebarRow()
                            } else {
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
                                    isSelected: coordinator.labelFilterSelection.visualSelection.contains(label.persistentModelID)
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
                                    toggleLabelSelection(label)
                                }
                                .draggable(DocumentLabelDragPayload.payload(for: label.id)) {
                                    // Set dragging state when drag begins
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

                                    Button(label.icon != nil ? "Change Icon" : "Set Icon") {
                                        editedIcon = label.icon ?? ""
                                        editingIconLabelID = label.persistentModelID
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            NSApp.orderFrontCharacterPalette(nil)
                                        }
                                    }

                                    if label.icon != nil {
                                        Button("Remove Icon") {
                                            changeIcon(of: label, to: nil)
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
                    }
                }
            }
            .padding(.vertical, 4)
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
        .alert("Set Icon", isPresented: editingIconBinding) {
            TextField("Emoji", text: $editedIcon)
            Button("Save") {
                commitIconEdit()
            }
            Button("Cancel", role: .cancel) {
                editingIconLabelID = nil
            }
        } message: {
            Text("Enter an emoji to use as the label icon.")
        }
        .onAppear {
            debugLogSidebarRenderTiming(startTime: renderStartTime, coordinator: coordinator)
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

    private func debugLogSidebarRenderTiming(startTime: TimeInterval, coordinator: LibraryCoordinator) {
        #if DEBUG
        let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
        Self.performanceLogger.log(
            "[Performance][SidebarRender] section=\(coordinator.selectedSection.rawValue, privacy: .public) labels=\(coordinator.allLabels.count) visualFilters=\(coordinator.labelFilterSelection.visualSelection.count) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
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

    private var editingIconBinding: Binding<Bool> {
        Binding(
            get: { editingIconLabelID != nil },
            set: { newValue in
                if !newValue {
                    editingIconLabelID = nil
                }
            }
        )
    }

    private func changeColor(of label: LabelTag, to color: LabelColor) {
        do {
            try ManageLabelsUseCase.changeColor(of: label, to: color, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeIcon(of label: LabelTag, to icon: String?) {
        do {
            try ManageLabelsUseCase.changeIcon(of: label, to: icon, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitIconEdit() {
        guard let editingIconLabelID,
              let label = coordinator.allLabels.first(where: { $0.persistentModelID == editingIconLabelID }) else {
            editingIconLabelID = nil
            return
        }

        let trimmed = editedIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon: String? = trimmed.isEmpty ? nil : String(trimmed.prefix(1))
        changeIcon(of: label, to: icon)
        self.editingIconLabelID = nil
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

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 14, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct LibraryLabelRowView: View {
    let name: String
    let color: Color
    var icon: String? = nil
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 12))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(name)
            Spacer()
            Text("\(count)")
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 14, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

    init(activeDocuments: [DocumentRecord], trashedCount: Int, labels: [LabelTag], recentLimit: Int) {
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
            .bin: trashedCount
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

private struct EmojiPickerButton: NSViewRepresentable {
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

private final class EmojiInputView: NSView, NSTextInputClient {
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

#Preview {
    LibrarySidebarView()
        .environment(LibraryCoordinator())
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
