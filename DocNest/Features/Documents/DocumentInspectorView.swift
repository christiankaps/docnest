import AppKit
import SwiftUI
import SwiftData

struct DocumentInspectorView: View {
    let documents: [DocumentRecord]
    let libraryURL: URL?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)]) private var allLabels: [LabelTag]
    @State private var newLabelName = ""
    @State private var inspectorErrorMessage: String?
    @State private var pendingDeletion: [DocumentRecord] = []
    @State private var editingTitle = ""
    @State private var isEditingTitle = false
    @State private var editingDocumentDate: Date = .now
    @State private var isEditingDocumentDate = false

    private var singleSelectedDocument: DocumentRecord? {
        documents.count == 1 ? documents.first : nil
    }

    private var selectionIsInBin: Bool {
        !documents.isEmpty && documents.allSatisfy { $0.trashedAt != nil }
    }

    var body: some View {
        Group {
            if let document = singleSelectedDocument {
                VSplitView {
                    pdfPreviewSection(for: document)
                        .frame(minHeight: 420, idealHeight: 620)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    ScrollView {
                        documentMetadataSection(for: document)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                    }
                    .frame(minHeight: 240, idealHeight: 320)
                }
                .navigationTitle("Preview")
            } else if !documents.isEmpty {
                multiSelectionInspector
                    .padding(24)
                    .navigationTitle("Selection")
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the list to inspect its metadata, labels, and preview.")
                )
            }
        }
        .confirmationDialog(
            pendingDeletionTitle,
            isPresented: pendingDeletionBinding,
            titleVisibility: .visible
        ) {
            Button(pendingDeletionActionTitle, role: .destructive) {
                confirmDeletionAction()
            }

            Button("Cancel", role: .cancel) {
                pendingDeletion = []
            }
        } message: {
            Text(pendingDeletionMessage)
        }
        .onChange(of: documents.first?.persistentModelID) {
            isEditingTitle = false
            isEditingDocumentDate = false
        }
        .alert("Inspector Error", isPresented: inspectorErrorBinding) {
            Button("OK", role: .cancel) {
                inspectorErrorMessage = nil
            }
        } message: {
            Text(inspectorErrorMessage ?? "Unknown inspector error.")
        }
    }

    @ViewBuilder
    private func pdfPreviewSection(for document: DocumentRecord) -> some View {
        if let path = document.storedFilePath,
           let libraryURL,
           DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) {
            PDFViewRepresentable(url: DocumentStorageService.fileURL(for: path, libraryURL: libraryURL))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if document.storedFilePath != nil {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red.opacity(0.6))
                        Text("File not found")
                            .font(AppTypography.sectionTitle)
                        Text("The stored PDF file for \"\(document.originalFileName)\" could not be located.")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                    .padding()
                }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No PDF file")
                            .font(AppTypography.sectionTitle)
                        Text("Import a PDF to see its preview.")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
        }
    }

    @ViewBuilder
    private func documentMetadataSection(for document: DocumentRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                if isEditingTitle {
                    TextField("Title", text: $editingTitle)
                        .font(AppTypography.title)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            commitTitleEdit(for: document)
                        }
                        .onExitCommand {
                            isEditingTitle = false
                        }
                } else {
                    Text(document.title)
                        .font(AppTypography.title)
                        .onTapGesture(count: 2) {
                            editingTitle = document.title
                            isEditingTitle = true
                        }
                        .help("Double-click to edit title")
                }

                Text(document.originalFileName)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)

                Text("Imported \(document.importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if isEditingDocumentDate {
                        DatePicker(
                            "Document Date",
                            selection: $editingDocumentDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)

                        Button("Save") {
                            commitDocumentDateEdit(for: document)
                        }
                        .buttonStyle(.borderless)

                        Button("Cancel") {
                            isEditingDocumentDate = false
                        }
                        .buttonStyle(.borderless)
                    } else if let sourceCreatedAt = document.sourceCreatedAt {
                        Text("Document Date \(sourceCreatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                            .onTapGesture(count: 2) {
                                editingDocumentDate = sourceCreatedAt
                                isEditingDocumentDate = true
                            }
                            .help("Double-click to edit document date")
                    } else {
                        Button("Set Document Date") {
                            editingDocumentDate = .now
                            isEditingDocumentDate = true
                        }
                        .buttonStyle(.borderless)
                        .font(AppTypography.body)
                    }
                }

                Text("\(document.pageCount) pages")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)

                Text(document.formattedFileSize)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }

            labelSection(for: document)

            if !document.contentHash.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Content Hash")
                        .font(AppTypography.sectionTitle)
                    Text(document.contentHash)
                        .font(AppTypography.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 12) {
                Button("Open Original") {
                    openOriginalFile(for: document)
                }
                .disabled(originalFileURL(for: document) == nil)

                Button("Show in Finder") {
                    showOriginalFileInFinder(for: document)
                }
                .disabled(originalFileURL(for: document) == nil)

                if let libraryURL {
                    Button("Show Library") {
                        NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
                    }
                }
            }

            documentDeletionSection(for: [document])
        }
    }

    private func originalFileURL(for document: DocumentRecord) -> URL? {
        guard let path = document.storedFilePath, let libraryURL else {
            return nil
        }

        guard DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) else {
            return nil
        }

        return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
    }

    private func openOriginalFile(for document: DocumentRecord) {
        guard let fileURL = originalFileURL(for: document) else {
            return
        }

        NSWorkspace.shared.open(fileURL)
    }

    private func showOriginalFileInFinder(for document: DocumentRecord) {
        guard let fileURL = originalFileURL(for: document) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @ViewBuilder
    private func labelSection(for document: DocumentRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Labels")
                    .font(AppTypography.sectionTitle)
            }

            if document.labels.isEmpty {
                Text("No labels assigned")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { label in
                        HStack {
                            LabelChip(name: label.name, color: label.labelColor)
                            Spacer()
                            Button {
                                removeLabel(label, from: document)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Menu("Assign Existing Label") {
                if allLabels.isEmpty {
                    Text("No labels available")
                } else {
                    ForEach(allLabels) { label in
                        Button {
                            toggleLabel(label, for: document)
                        } label: {
                            HStack {
                                Text(label.name)
                                if document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Create and assign label", text: $newLabelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        createAndAssignLabel(to: document)
                    }

                Button("Add") {
                    createAndAssignLabel(to: document)
                }
                .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var multiSelectionInspector: some View {
        let selectionSummary = BatchLabelSelectionSummary(documents: documents, availableLabels: allLabels)

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(documents.count) Documents Selected")
                    .font(AppTypography.title)

                Text("Use this inspector to add or remove labels across the current selection without changing the imported originals.")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Shared Labels")
                        .font(AppTypography.sectionTitle)
                }

                if selectionSummary.labelsOnAllSelectedDocuments.isEmpty {
                    Text("No label is currently assigned to every selected document.")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectionSummary.labelsOnAllSelectedDocuments) { label in
                            HStack {
                                LabelChip(name: label.name, color: label.labelColor)
                                Spacer()
                                Button("Remove from Selection") {
                                    removeLabel(label, from: documents)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            if !selectionSummary.partiallyAssignedLabels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Partially Assigned")
                        .font(AppTypography.sectionTitle)

                    Text(selectionSummary.partiallyAssignedLabels.map(\.name).joined(separator: ", "))
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            Menu("Apply or Remove Existing Label") {
                if allLabels.isEmpty {
                    Text("No labels available")
                } else {
                    ForEach(allLabels) { label in
                        Button {
                            toggleLabel(label, for: documents)
                        } label: {
                            HStack {
                                Text(label.name)
                                Spacer()
                                Text(selectionSummary.actionTitle(for: label))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Create and assign label to selection", text: $newLabelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        createAndAssignLabel(to: documents)
                    }

                Button("Add to Selection") {
                    createAndAssignLabel(to: documents)
                }
                .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            documentDeletionSection(for: documents)

            Spacer()
        }
    }

    @ViewBuilder
    private func documentDeletionSection(for documents: [DocumentRecord]) -> some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Delete")
                .font(AppTypography.sectionTitle)

            Text(deletionHelpText(for: documents))
                .font(AppTypography.body)
                .foregroundStyle(.secondary)

            Button(selectionIsInBin ? (documents.count == 1 ? "Delete Permanently" : "Delete Selection Permanently") : (documents.count == 1 ? "Delete Document" : "Delete Selection")) {
                promptDeletionAction(for: documents)
            }
            .foregroundStyle(.red)
        }
    }

    private var inspectorErrorBinding: Binding<Bool> {
        Binding(
            get: { inspectorErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    inspectorErrorMessage = nil
                }
            }
        )
    }

    private var pendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { !pendingDeletion.isEmpty },
            set: { newValue in
                if !newValue {
                    pendingDeletion = []
                }
            }
        )
    }

    private func toggleLabel(_ label: LabelTag, for document: DocumentRecord) {
        toggleLabel(label, for: [document])
    }

    private func toggleLabel(_ label: LabelTag, for documents: [DocumentRecord]) {
        do {
            if documents.allSatisfy({ document in
                document.labels.contains(where: { $0.persistentModelID == label.persistentModelID })
            }) {
                try ManageLabelsUseCase.remove(label, from: documents, using: modelContext)
            } else {
                try ManageLabelsUseCase.assign(label, to: documents, using: modelContext)
            }
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
    }

    private func removeLabel(_ label: LabelTag, from document: DocumentRecord) {
        removeLabel(label, from: [document])
    }

    private func removeLabel(_ label: LabelTag, from documents: [DocumentRecord]) {
        do {
            try ManageLabelsUseCase.remove(label, from: documents, using: modelContext)
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
    }

    private func createAndAssignLabel(to document: DocumentRecord) {
        createAndAssignLabel(to: [document])
    }

    private func createAndAssignLabel(to documents: [DocumentRecord]) {
        do {
            _ = try ManageLabelsUseCase.createAndAssignLabel(named: newLabelName, to: documents, using: modelContext)
            newLabelName = ""
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
    }

    private func commitTitleEdit(for document: DocumentRecord) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingTitle = false
            return
        }

        document.title = trimmed
        do {
            try modelContext.save()
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
        isEditingTitle = false
    }

    private func commitDocumentDateEdit(for document: DocumentRecord) {
        document.sourceCreatedAt = editingDocumentDate
        do {
            try modelContext.save()
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
        isEditingDocumentDate = false
    }

    private func promptDeletionAction(for documents: [DocumentRecord]) {
        pendingDeletion = documents
    }

    private func confirmDeletionAction() {
        guard !pendingDeletion.isEmpty else {
            return
        }

        do {
            if pendingDeletion.allSatisfy({ $0.trashedAt != nil }) {
                let removalMode: DocumentDeletionMode = libraryURL == nil ? .removeFromLibrary : .deleteStoredFiles
                try DeleteDocumentsUseCase.execute(
                    pendingDeletion,
                    mode: removalMode,
                    libraryURL: libraryURL,
                    using: modelContext
                )
            } else {
                try DeleteDocumentsUseCase.moveToBin(pendingDeletion, using: modelContext)
            }
            pendingDeletion = []
        } catch {
            pendingDeletion = []
            inspectorErrorMessage = error.localizedDescription
        }
    }

    private func deletionHelpText(for documents: [DocumentRecord]) -> String {
        if documents.allSatisfy({ $0.trashedAt != nil }) {
            if documents.count == 1 {
                return "Deleting from Bin removes the document permanently from the library."
            }

            return "Deleting from Bin removes all selected documents permanently from the library."
        }

        if documents.count == 1 {
            return "Deleting moves the document to Bin first, so it can be restored later."
        }

        return "Deleting moves all selected documents to Bin first, so they can be restored later."
    }

    private var pendingDeletionTitle: String {
        if pendingDeletion.allSatisfy({ $0.trashedAt != nil }) {
            return pendingDeletion.count == 1 ? "Delete Document Permanently" : "Delete Documents Permanently"
        }

        return pendingDeletion.count == 1 ? "Move Document To Bin" : "Move Documents To Bin"
    }

    private var pendingDeletionActionTitle: String {
        if pendingDeletion.allSatisfy({ $0.trashedAt != nil }) {
            return pendingDeletion.count == 1 ? "Delete Permanently" : "Delete Selection Permanently"
        }

        return pendingDeletion.count == 1 ? "Move to Bin" : "Move Selection to Bin"
    }

    private var pendingDeletionMessage: String {
        if pendingDeletion.allSatisfy({ $0.trashedAt != nil }) {
            if pendingDeletion.count == 1 {
                return "This removes the document permanently from the library and deletes its stored PDF file. This action cannot be undone."
            }

            return "This removes the selected documents permanently from the library and deletes their stored PDF files. This action cannot be undone."
        }

        if pendingDeletion.count == 1 {
            return "The document will be moved to Bin and can be restored later."
        }

        return "The selected documents will be moved to Bin and can be restored later."
    }
}

private struct BatchLabelSelectionSummary {
    let documents: [DocumentRecord]
    let availableLabels: [LabelTag]

    var labelsOnAllSelectedDocuments: [LabelTag] {
        labelStates.filter(\.isAssignedToAllSelectedDocuments).map(\.label)
    }

    var partiallyAssignedLabels: [LabelTag] {
        labelStates.filter(\.isPartiallyAssigned).map(\.label)
    }

    func actionTitle(for label: LabelTag) -> String {
        guard let state = labelStates.first(where: { $0.label.persistentModelID == label.persistentModelID }) else {
            return "Add to all"
        }

        if state.isAssignedToAllSelectedDocuments {
            return "Remove from all"
        }

        if state.isPartiallyAssigned {
            return "Add to remaining"
        }

        return "Add to all"
    }

    private var labelStates: [BatchLabelState] {
        availableLabels.compactMap { label in
            let assignedDocumentCount = documents.reduce(into: 0) { count, document in
                if document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) {
                    count += 1
                }
            }

            guard assignedDocumentCount > 0 else {
                return nil
            }

            return BatchLabelState(
                label: label,
                assignedDocumentCount: assignedDocumentCount,
                selectedDocumentCount: documents.count
            )
        }
        .sorted { $0.label.name.localizedCaseInsensitiveCompare($1.label.name) == .orderedAscending }
    }
}

private struct BatchLabelState {
    let label: LabelTag
    let assignedDocumentCount: Int
    let selectedDocumentCount: Int

    var isAssignedToAllSelectedDocuments: Bool {
        assignedDocumentCount == selectedDocumentCount
    }

    var isPartiallyAssigned: Bool {
        assignedDocumentCount > 0 && assignedDocumentCount < selectedDocumentCount
    }
}

private enum DocumentInspectorPreviewData {
    @MainActor
    static func make() -> (container: ModelContainer, document: DocumentRecord) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: DocumentRecord.self, configurations: config)

        let labels = LabelTag.makeSamples()
        container.mainContext.insert(labels.finance)
        container.mainContext.insert(labels.tax)

        let document = DocumentRecord(
            originalFileName: "invoice-march-2026.pdf",
            title: "Invoice March 2026",
            sourceCreatedAt: .now.addingTimeInterval(-86_400 * 2),
            importedAt: .now,
            pageCount: 4,
            fileSize: 182_144,
            contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            labels: [labels.finance, labels.tax]
        )
        container.mainContext.insert(document)

        return (container, document)
    }
}

#Preview {
    let previewData = DocumentInspectorPreviewData.make()

    DocumentInspectorView(documents: [previewData.document], libraryURL: nil)
        .modelContainer(previewData.container)
}