import AppKit
import OSLog
import SwiftUI
import SwiftData

struct DocumentInspectorView: View {
    let documents: [DocumentRecord]
    let libraryURL: URL?
    let isTransitioningSelection: Bool

    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var newLabelName = ""
    @State private var inspectorErrorMessage: String?
    @State private var pendingDeletion: [DocumentRecord] = []
    @State private var editingTitle = ""
    @State private var isEditingTitle = false
    @State private var dateFieldText = ""
    @State private var selectedFileAvailable: Bool?
    @State private var selectedFileAvailabilitySignature = 0
    @State private var selectedFileAvailabilityTask: Task<Void, Never>?
    @State private var cachedSelectionSummary = BatchLabelSelectionSummary.empty
    @State private var cachedSelectionSummarySignature = 0

    private var singleSelectedDocument: DocumentRecord? {
        documents.count == 1 ? documents.first : nil
    }

    private var selectionIsInBin: Bool {
        !documents.isEmpty && documents.allSatisfy { $0.trashedAt != nil }
    }

    private var multiSelectionSummarySignature: Int {
        var hasher = Hasher()
        for document in documents {
            hasher.combine(document.persistentModelID)
            hasher.combine(document.labels.count)
            hasher.combine(document.trashedAt)
        }
        for label in coordinator.allLabels {
            hasher.combine(label.persistentModelID)
            hasher.combine(label.name)
            hasher.combine(label.groupID)
        }
        return hasher.finalize()
    }

    var body: some View {
        Group {
            if let document = singleSelectedDocument {
                singleDocumentInspector(for: document)
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
        .overlay(alignment: .topTrailing) {
            if isTransitioningSelection {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
                .transition(.opacity)
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
            dateFieldText = formattedDateString(from: singleSelectedDocument?.documentDate)
            refreshSelectedFileAvailability()
        }
        .onAppear {
            refreshSelectedFileAvailability()
        }
        .onChange(of: libraryURL?.path) {
            refreshSelectedFileAvailability()
        }
        .task(id: multiSelectionSummarySignature) {
            refreshCachedSelectionSummaryIfNeeded()
        }
        .onDisappear {
            selectedFileAvailabilityTask?.cancel()
            selectedFileAvailabilityTask = nil
            selectedFileAvailabilitySignature = 0
        }
        .alert("Inspector Error", isPresented: inspectorErrorBinding) {
            Button("OK", role: .cancel) {
                inspectorErrorMessage = nil
            }
        } message: {
            Text(inspectorErrorMessage ?? "Unknown inspector error.")
        }
    }

    private func singleDocumentInspector(for document: DocumentRecord) -> some View {
        VSplitView {
            DocumentPreviewPane(
                document: document,
                libraryURL: libraryURL,
                selectedFileAvailable: selectedFileAvailable
            )
            .frame(minHeight: 420, idealHeight: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                documentMetadataSection(for: document)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .frame(minHeight: 240, idealHeight: 320)
        }
        .navigationTitle("Preview")
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func pdfPreviewSection(for document: DocumentRecord) -> some View {
        if let path = document.storedFilePath, let libraryURL {
            if selectedFileAvailable ?? true {
                PDFViewRepresentable(url: DocumentStorageService.fileURL(for: path, libraryURL: libraryURL))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
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
            }
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
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Document Date")
                            .font(AppTypography.sectionTitle)

                        Spacer()

                        Button {
                            coordinator.reExtractDocumentDate(for: [document], modelContext: modelContext)
                            dateFieldText = formattedDateString(from: document.documentDate)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Re-extract date from document text")
                        .disabled(document.fullText == nil || document.fullText?.isEmpty == true)

                        if document.documentDate != nil || !dateFieldText.isEmpty {
                            Button {
                                document.documentDate = nil
                                dateFieldText = ""
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear document date")
                        }
                    }

                    TextField("DD.MM.YYYY", text: $dateFieldText)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                        .onChange(of: dateFieldText) {
                            applyDateMask(for: document)
                        }
                        .onAppear {
                            dateFieldText = formattedDateString(from: document.documentDate)
                        }

                    if document.documentDate == nil && dateFieldText.isEmpty {
                        Text("Type a date, e.g. 01.03.2026")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(document.pageCount) pages")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)

                Text(document.formattedFileSize)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }

            Divider()
            labelSection(for: document)

            Divider()
            textExtractionSection(for: document)

            if !document.contentHash.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Content Hash")
                        .font(AppTypography.sectionLabel)
                    Text(document.contentHash)
                        .font(AppTypography.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            let resolvedFileURL = originalFileURL(for: document)
            Divider()
            HStack(spacing: 12) {
                Button("Open Original") {
                    if let fileURL = resolvedFileURL {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
                .disabled(resolvedFileURL == nil)

                Button("Show in Finder") {
                    if let fileURL = resolvedFileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
                .disabled(resolvedFileURL == nil)

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

        if singleSelectedDocument?.persistentModelID == document.persistentModelID,
           selectedFileAvailable == false {
            return nil
        }

        guard DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) else {
            return nil
        }

        return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
    }

    @ViewBuilder
    private func labelSection(for document: DocumentRecord) -> some View {
        let availableLabels = coordinator.allLabels

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Labels")
                    .font(AppTypography.sectionLabel)
            }

            if document.labels.isEmpty {
                Text("No labels assigned")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.labels) { label in
                        HStack {
                            LabelChip(name: label.name, color: label.labelColor, icon: label.icon)
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
                if availableLabels.isEmpty {
                    Text("No labels available")
                } else {
                    ForEach(availableLabels) { label in
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

    @ViewBuilder
    private func textExtractionSection(for document: DocumentRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text Extraction")
                .font(AppTypography.sectionLabel)

            HStack(spacing: 6) {
                if document.ocrCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let text = document.fullText, !text.isEmpty {
                        Text("Extracted (\(text.count) characters)")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No text found")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                    }
                } else if document.fullText != nil {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Legacy extraction (no OCR)")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    Text("Pending extraction")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Re-extract Text") {
                guard let libraryURL = coordinator.libraryURL, let modelContext = coordinator.modelContext else { return }
                coordinator.reExtractText(for: [document], libraryURL: libraryURL, modelContext: modelContext)
            }
            .disabled(document.storedFilePath == nil)
        }
    }

    private var multiSelectionInspector: some View {
        let availableLabels = coordinator.allLabels
        let selectionSummary = cachedSelectionSummary

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
                        .font(AppTypography.sectionLabel)
                }

                if selectionSummary.labelsOnAllSelectedDocuments.isEmpty {
                    Text("No label is currently assigned to every selected document.")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectionSummary.labelsOnAllSelectedDocuments) { label in
                            HStack {
                                LabelChip(name: label.name, color: label.labelColor, icon: label.icon)
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
                        .font(AppTypography.sectionLabel)

                    Text(selectionSummary.partiallyAssignedLabels.map(\.name).joined(separator: ", "))
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            Menu("Apply or Remove Existing Label") {
                if availableLabels.isEmpty {
                    Text("No labels available")
                } else {
                    ForEach(availableLabels) { label in
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
                .font(AppTypography.sectionLabel)

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

        if let storedFilePath = document.storedFilePath, let libraryURL {
            document.storedFilePath = DocumentStorageService.renameStoredFile(
                at: storedFilePath,
                newTitle: trimmed,
                contentHash: document.contentHash,
                libraryURL: libraryURL
            )
        }

        do {
            try modelContext.save()
        } catch {
            inspectorErrorMessage = error.localizedDescription
        }
        isEditingTitle = false
    }

    private static let germanDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        f.isLenient = false
        return f
    }()

    private func formattedDateString(from date: Date?) -> String {
        guard let date else { return "" }
        return Self.germanDateFormatter.string(from: date)
    }

    private func applyDateMask(for document: DocumentRecord) {
        // Strip non-digits
        let digits = dateFieldText.filter(\.isWholeNumber)
        let clamped = String(digits.prefix(8))

        // Re-insert dots after DD and MM
        var masked = ""
        for (i, ch) in clamped.enumerated() {
            if i == 2 || i == 4 { masked.append(".") }
            masked.append(ch)
        }

        if dateFieldText != masked {
            dateFieldText = masked
            return // onChange will re-fire with the corrected value
        }

        // When we have a full date (8 digits → DD.MM.YYYY), try to parse and save
        if clamped.count == 8 {
            if let parsed = Self.germanDateFormatter.date(from: masked),
               Self.germanDateFormatter.string(from: parsed) == masked {
                document.documentDate = parsed
                try? modelContext.save()
            }
        }
    }

    private func refreshSelectedFileAvailability() {
        guard let document = singleSelectedDocument,
              let path = document.storedFilePath,
              let libraryURL else {
            selectedFileAvailabilityTask?.cancel()
            selectedFileAvailabilityTask = nil
            selectedFileAvailabilitySignature = 0
            selectedFileAvailable = nil
            return
        }

        var hasher = Hasher()
        hasher.combine(document.persistentModelID)
        hasher.combine(path)
        hasher.combine(libraryURL.path)
        let signature = hasher.finalize()

        guard signature != selectedFileAvailabilitySignature else { return }

        selectedFileAvailabilityTask?.cancel()
        selectedFileAvailabilitySignature = signature
        let targetID = document.persistentModelID
        selectedFileAvailabilityTask = Task {
            let exists = await DocumentStorageService.fileExistsAsync(at: path, libraryURL: libraryURL)
            guard !Task.isCancelled else { return }
            guard self.singleSelectedDocument?.persistentModelID == targetID else { return }
            self.selectedFileAvailable = exists
            self.selectedFileAvailabilityTask = nil
        }
    }

    private func refreshCachedSelectionSummaryIfNeeded() {
        guard documents.count > 1 else {
            cachedSelectionSummary = .empty
            cachedSelectionSummarySignature = 0
            return
        }
        let signature = multiSelectionSummarySignature
        guard signature != cachedSelectionSummarySignature else { return }
        #if DEBUG
        let startTime = Date().timeIntervalSinceReferenceDate
        #endif
        cachedSelectionSummary = BatchLabelSelectionSummary(
            documents: documents,
            availableLabels: coordinator.allLabels
        )
        cachedSelectionSummarySignature = signature
        #if DEBUG
        let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
        Logger(subsystem: "com.kaps.docnest", category: "performance").log(
            "[Performance][SelectionSummary] documents=\(documents.count) labels=\(coordinator.allLabels.count) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
        )
        #endif
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

private struct DocumentPreviewPane: View {
    let document: DocumentRecord
    let libraryURL: URL?
    let selectedFileAvailable: Bool?

    var body: some View {
        Group {
            if let path = document.storedFilePath, let libraryURL {
                if selectedFileAvailable ?? true {
                    PDFViewRepresentable(url: DocumentStorageService.fileURL(for: path, libraryURL: libraryURL))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                        .id(document.persistentModelID)
                } else {
                    missingFileContent
                }
            } else if document.storedFilePath != nil {
                missingFileContent
            } else {
                placeholderCard(
                    icon: "doc.text.magnifyingglass",
                    iconColor: .secondary,
                    title: "No PDF file",
                    message: "Import a PDF to see its preview."
                )
            }
        }
    }

    private var missingFileContent: some View {
        placeholderCard(
            icon: "exclamationmark.triangle",
            iconColor: .red.opacity(0.7),
            title: "File not found",
            message: "The stored PDF file for \"\(document.originalFileName)\" could not be located."
        )
    }

    private func placeholderCard(icon: String, iconColor: Color, title: String, message: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(AppTypography.sectionLabel)
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .padding(28)
            }
    }
}

private struct BatchLabelSelectionSummary {
    let labelsOnAllSelectedDocuments: [LabelTag]
    let partiallyAssignedLabels: [LabelTag]
    private let labelStatesByID: [PersistentIdentifier: BatchLabelState]

    static let empty = BatchLabelSelectionSummary(
        labelsOnAllSelectedDocuments: [],
        partiallyAssignedLabels: [],
        labelStatesByID: [:]
    )

    private init(
        labelsOnAllSelectedDocuments: [LabelTag],
        partiallyAssignedLabels: [LabelTag],
        labelStatesByID: [PersistentIdentifier: BatchLabelState]
    ) {
        self.labelsOnAllSelectedDocuments = labelsOnAllSelectedDocuments
        self.partiallyAssignedLabels = partiallyAssignedLabels
        self.labelStatesByID = labelStatesByID
    }

    init(documents: [DocumentRecord], availableLabels: [LabelTag]) {
        let states: [BatchLabelState] = availableLabels.compactMap { label in
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

        labelsOnAllSelectedDocuments = states.filter(\.isAssignedToAllSelectedDocuments).map(\.label)
        partiallyAssignedLabels = states.filter(\.isPartiallyAssigned).map(\.label)
        labelStatesByID = Dictionary(uniqueKeysWithValues: states.map { ($0.label.persistentModelID, $0) })
    }

    func actionTitle(for label: LabelTag) -> String {
        guard let state = labelStatesByID[label.persistentModelID] else {
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
    static func make() -> (container: ModelContainer, document: DocumentRecord)? {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: DocumentRecord.self, configurations: config) else {
            return nil
        }

        let labels = LabelTag.makeSamples()
        container.mainContext.insert(labels.finance)
        container.mainContext.insert(labels.tax)

        let document = DocumentRecord(
            originalFileName: "invoice-march-2026.pdf",
            title: "Invoice March 2026",
            documentDate: .now.addingTimeInterval(-86_400 * 2),
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
    if let previewData = DocumentInspectorPreviewData.make() {
        DocumentInspectorView(documents: [previewData.document], libraryURL: nil, isTransitioningSelection: false)
            .environment(LibraryCoordinator())
            .modelContainer(previewData.container)
    } else {
        ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
    }
}
