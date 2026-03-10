import AppKit
import SwiftUI
import SwiftData

struct DocumentInspectorView: View {
    let document: DocumentRecord?
    let libraryURL: URL?
    let onManageLabels: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LabelTag.name, order: .forward) private var allLabels: [LabelTag]
    @State private var newLabelName = ""
    @State private var labelErrorMessage: String?

    var body: some View {
        Group {
            if let document {
                VStack(alignment: .leading, spacing: 20) {
                    pdfPreviewSection(for: document)
                        .frame(maxHeight: 360)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(document.originalFileName)
                            .foregroundStyle(.secondary)

                        Text("Imported \(document.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)

                        if let sourceCreatedAt = document.sourceCreatedAt {
                            Text("Created \(sourceCreatedAt.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }

                        Text("\(document.pageCount) pages")
                            .foregroundStyle(.secondary)

                        Text(document.formattedFileSize)
                            .foregroundStyle(.secondary)
                    }

                    labelSection(for: document)

                    if !document.contentHash.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Content Hash")
                                .font(.headline)
                            Text(document.contentHash)
                                .font(.caption.monospaced())
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

                    Spacer()
                }
                .padding(24)
                .navigationTitle("Preview")
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the list to inspect its metadata, labels, and preview.")
                )
            }
        }
        .alert("Label Error", isPresented: labelErrorBinding) {
            Button("OK", role: .cancel) {
                labelErrorMessage = nil
            }
        } message: {
            Text(labelErrorMessage ?? "Unknown label error.")
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
                            .font(.headline)
                        Text("The stored PDF file could not be located.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                            .font(.headline)
                        Text("Import a PDF to see its preview.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
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
                    .font(.headline)
                Spacer()
                Button("Manage Labels", action: onManageLabels)
            }

            if document.labels.isEmpty {
                Text("No labels assigned")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { label in
                        HStack {
                            LabelChip(name: label.name)
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

    private var labelErrorBinding: Binding<Bool> {
        Binding(
            get: { labelErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    labelErrorMessage = nil
                }
            }
        )
    }

    private func toggleLabel(_ label: LabelTag, for document: DocumentRecord) {
        do {
            if document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) {
                try ManageLabelsUseCase.remove(label, from: document, using: modelContext)
            } else {
                try ManageLabelsUseCase.assign(label, to: document, using: modelContext)
            }
        } catch {
            labelErrorMessage = error.localizedDescription
        }
    }

    private func removeLabel(_ label: LabelTag, from document: DocumentRecord) {
        do {
            try ManageLabelsUseCase.remove(label, from: document, using: modelContext)
        } catch {
            labelErrorMessage = error.localizedDescription
        }
    }

    private func createAndAssignLabel(to document: DocumentRecord) {
        do {
            _ = try ManageLabelsUseCase.createAndAssignLabel(named: newLabelName, to: document, using: modelContext)
            newLabelName = ""
        } catch {
            labelErrorMessage = error.localizedDescription
        }
    }
}

private struct LabelChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
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

    DocumentInspectorView(document: previewData.document, libraryURL: nil, onManageLabels: {})
        .modelContainer(previewData.container)
}