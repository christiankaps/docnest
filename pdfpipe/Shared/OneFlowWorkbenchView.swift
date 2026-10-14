import SwiftUI

struct OneFlowWorkbenchView: View {
    @ObservedObject var model: OneFlowSessionModel
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var exportedName: String?
    @State private var preparingExport = false
    @State private var showingDetails = false
    @ScaledMetric(relativeTo: .body) private var cloudSize: CGFloat = 15

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.phase {
                    case .idle:
                        ContentUnavailableView("No document", systemImage: "doc",
                            description: Text("Open one PDF, JPEG, or PNG file to begin."))
                    case .processing:
                        processingProgress
                        if let document = model.document {
                            documentHeader(document)
                        }
                    case .ready:
                        if let document = model.document {
                            documentHeader(document)
                            Label(model.ocrStatus, systemImage: "text.viewfinder")
                                .font(.subheadline).foregroundStyle(.secondary)
                            DisclosureGroup("Document details", isExpanded: $showingDetails) {
                                details(document.facts)
                            }
                            dateSection
                            wordSection
                            namingSection
                        }
                    case .finished(let filename):
                        ContentUnavailableView {
                            Label("Finished", systemImage: "checkmark.circle.fill")
                        } description: {
                            Text(filename)
                        } actions: {
                            Button("Done") { model.discard() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(model.phase == .processing || model.phase == .ready ? "Name PDF" : "PDF Pipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.phase == .ready || model.phase == .idle {
                        Button("Discard", role: .destructive) { model.discard() }
                            .disabled(preparingExport)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.phase == .ready {
                    exportActions
                        .padding(.horizontal).padding(.vertical, 10)
                        .background(.bar)
                }
            }
            .interactiveDismissDisabled()
            .alert("PDF Pipe", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } }),
                onDismiss: finishExport) {
                if let shareURL {
                    SharePicker(url: shareURL) { completed, error in
                        if let error { model.error = error }
                        if completed { exportedName = shareURL.lastPathComponent }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } }),
                onDismiss: finishExport) {
                if let exportURL {
                    ExportPicker(url: exportURL) { completed, name in
                        if completed { exportedName = name ?? exportURL.lastPathComponent }
                    }
                }
            }
        }
        .tint(PipeAppearance.accent)
    }

    @ViewBuilder private func documentHeader(_ document: SessionDocument) -> some View {
        PDFPreview(url: document.url)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("PDF preview")
        originCard(document.facts.origin)
    }

    private var processingProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Processing document", systemImage: "doc.text.viewfinder")
                .font(.headline)
            Text(model.progress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("processingStatus")
            ProgressView(value: model.progressFraction, total: 1)
                .progressViewStyle(.linear)
                .accessibilityLabel("Processing progress")
                .accessibilityIdentifier("processingProgress")
            Button("Cancel processing", role: .cancel) { model.discard() }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func details(_ facts: DocumentFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(facts.filename).textSelection(.enabled)
            Text("\(facts.pages) pages · \(ByteCountFormatter.string(fromByteCount: facts.bytes, countStyle: .file))")
            Text("Source: \(facts.sourceFormat) · \(facts.dimensions)")
            Text(facts.hasText ? "Embedded text available" : "No embedded text before OCR")
        }.font(.subheadline).foregroundStyle(.secondary)
    }

    private func originCard(_ origin: DocumentOrigin) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: origin.symbol)
                .font(.title3)
                .foregroundStyle(PipeAppearance.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(origin.title).font(.subheadline.weight(.semibold))
                Text(origin.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("documentOrigin")
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dates").font(.headline)
            if model.analysis.dates.isEmpty {
                Text("No date found in the document. Processing date is available as a fallback.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(model.dateSuggestions) { date in
                    let id = "date:\(date.value)"
                    let order = model.composer.order(of: id)
                    Button { model.toggleDate(date.value) } label: {
                        Label(date.value + (model.analysis.dates.isEmpty ? " · Fallback" : ""),
                            systemImage: order == nil ? "calendar" : "\(order!).circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(order != nil ? .orange : PipeAppearance.accent)
                    .accessibilityLabel("\(date.value), \(order.map { "selected position \($0)" } ?? "not selected")")
                }
            }
        }
    }

    private var wordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested words").font(.headline)
            if model.analysis.words.isEmpty {
                Text("No useful words found. Type a word or a complete filename below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let highest = max(model.analysis.words.first?.score ?? 1, 1)
                FlowLayout(spacing: 8) {
                    ForEach(model.analysis.words) { word in
                        let order = model.composer.order(of: "word:\(word.id)")
                        Button { model.toggleWord(word) } label: {
                            HStack(spacing: 5) {
                                if let order { Text("\(order).").font(.caption.bold()) }
                                Text(word.text)
                            }
                            .font(.system(size: cloudSize + CGFloat(3 * word.score / highest),
                                weight: word.score / highest > 0.7 ? .semibold : .regular))
                        }
                        .buttonStyle(.bordered)
                        .tint(order != nil ? PipeAppearance.accent : .secondary)
                        .accessibilityLabel("\(word.text), \(order.map { "selected position \($0)" } ?? "not selected")")
                    }
                }
            }
            HStack {
                TextField("Add a word", text: $model.manualWord)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("manualWord")
                Button("Add") { model.addManualWord() }
                    .disabled(model.manualWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filename").font(.headline)
            Picker("Join with", selection: Binding(get: { model.composer.separator }, set: { model.setSeparator($0) })) {
                Text("-").tag(FilenameComposer.Separator.dash)
                Text("_").tag(FilenameComposer.Separator.underscore)
            }.pickerStyle(.segmented)
            Text("The separator applies to the next word or date you add.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.composer.parts.isEmpty {
                Text(model.composer.parts.enumerated().map { "\($0.offset + 1). \($0.element.value)" }.joined(separator: "   "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("Type a filename", text: Binding(
                get: { model.composer.stem },
                set: { model.editFilename($0) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("filename")
            if model.composer.undoParts != nil {
                Button("Undo manual edit") { model.undoFilenameEdit() }
            }
            switch model.composer.validFilename {
            case .success(let name):
                Label(name, systemImage: "checkmark.circle")
                    .font(.subheadline).textSelection(.enabled)
                    .accessibilityIdentifier("proposedFilename")
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.red)
            }
        }
    }

    private var exportActions: some View {
        HStack {
            Button { prepareExport(share: true) } label: {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            Button { prepareExport(share: false) } label: {
                Label("Save to Files", systemImage: "folder").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled((try? model.composer.validFilename.get()) == nil || preparingExport)
    }

    private func prepareExport(share: Bool) {
        preparingExport = true
        Task {
            defer { preparingExport = false }
            do {
                let url = try await model.prepareExport()
                if share { shareURL = url } else { exportURL = url }
            } catch { model.error = error.localizedDescription }
        }
    }

    private func finishExport() {
        if let exportedName { model.exported(exportedName); self.exportedName = nil }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 350, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(width: bounds.width, subviews: subviews).positions
        for (index, position) in positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
