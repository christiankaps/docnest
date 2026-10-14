import SwiftUI

struct OneFlowWorkbenchView: View {
    @ObservedObject var model: OneFlowSessionModel
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var exportedName: String?
    @State private var preparingExport = false
    @State private var showingDetails = false
    @State private var showingTextInspection = false
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
                        VStack(alignment: .leading, spacing: 16) {
                            ProgressView(model.progress)
                            Button("Cancel processing", role: .cancel) { model.discard() }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    case .ready:
                        if let document = model.document {
                            PDFPreview(url: document.url)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityLabel("PDF preview")
                            Label(model.ocrStatus, systemImage: "text.viewfinder")
                                .font(.subheadline).foregroundStyle(.secondary)
                            textSourceSection
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
            .navigationTitle(model.phase == .ready ? "Name PDF" : "PDF Pipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .finished = model.phase { } else {
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
            .sheet(isPresented: $showingTextInspection) {
                TextInspectionView(model: model)
            }
        }
        .tint(PipeAppearance.accent)
    }

    private func details(_ facts: DocumentFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(facts.filename).textSelection(.enabled)
            Text("\(facts.pages) pages · \(ByteCountFormatter.string(fromByteCount: facts.bytes, countStyle: .file))")
            Text("Source: \(facts.sourceFormat) · \(facts.dimensions)")
            Text(facts.hasText ? "Embedded text available" : "No embedded text before OCR")
        }.font(.subheadline).foregroundStyle(.secondary)
    }

    private var textSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Text source · Debug", systemImage: "ladybug")
                .font(.subheadline.weight(.semibold))
            Picker("Suggestions from", selection: $model.inspectionSource) {
                ForEach(InspectionSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("textSourcePicker")
            Text("Dates and words update with the selected text. Your filename stays as composed.")
                .font(.caption).foregroundStyle(.secondary)
            Button("View full text and diff", systemImage: "doc.text.magnifyingglass") {
                showingTextInspection = true
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dates").font(.headline)
            if model.analysis.dates.isEmpty {
                Text("No date found in the document. Processing date is available as a fallback.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(Array(model.dateSuggestions.enumerated()), id: \.element.id) { index, date in
                    let id = "date:\(date.value)"
                    let order = model.composer.order(of: id)
                    Button { model.toggleDate(date.value) } label: {
                        Label(date.value + (index == 0 && !model.analysis.dates.isEmpty ? " · Suggested" :
                            model.analysis.dates.isEmpty ? " · Fallback" : ""),
                            systemImage: order == nil ? "calendar" : "\(order!).circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(index == 0 && !model.analysis.dates.isEmpty ? .orange : PipeAppearance.accent)
                    .accessibilityLabel("\(date.value), \(index == 0 && !model.analysis.dates.isEmpty ? "suggested date, " : "")\(order.map { "selected position \($0)" } ?? "not selected")")
                }
            }
        }
    }

    private var wordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested words").font(.headline)
            Text("Hold a word to rate it. Your rating changes future suggestions, not this document.")
                .font(.caption).foregroundStyle(.secondary)
            if model.analysis.words.isEmpty {
                Text("No useful words found. Type a word or a complete filename below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let highest = max(model.analysis.words.first?.score ?? 1, 1)
                FlowLayout(spacing: 8) {
                    ForEach(model.analysis.words) { word in
                        let order = model.composer.order(of: "word:\(word.id)")
                        let vote = model.vote(for: word)
                        Menu {
                            Button { model.setVote(.up, for: word) } label: {
                                Label("More important", systemImage: vote == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                            }
                            Button { model.setVote(.down, for: word) } label: {
                                Label("Less important", systemImage: vote == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            }
                            if vote != nil {
                                Button { model.setVote(nil, for: word) } label: {
                                    Label("Remove rating", systemImage: "arrow.uturn.backward")
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if let order { Text("\(order).").font(.caption.bold()) }
                                Text(word.text)
                                if let vote {
                                    Image(systemName: vote == .up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.system(size: cloudSize + CGFloat(3 * word.score / highest),
                                weight: word.score / highest > 0.7 ? .semibold : .regular))
                        } primaryAction: { model.toggleWord(word) }
                        .buttonStyle(.bordered)
                        .tint(order != nil ? PipeAppearance.accent : vote == .up ? .green : vote == .down ? .orange : .secondary)
                        .accessibilityLabel("\(word.text), \(order.map { "selected position \($0)" } ?? "not selected"), \(vote == .up ? "rated more important" : vote == .down ? "rated less important" : "not rated")")
                        .accessibilityAction(named: "More important") { model.setVote(.up, for: word) }
                        .accessibilityAction(named: "Less important") { model.setVote(.down, for: word) }
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

private struct TextInspectionView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case text = "Full text"
        case diff = "Diff"
        var id: Self { self }
    }

    @ObservedObject var model: OneFlowSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .text

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                    }
                    .pickerStyle(.segmented)
                    if tab == .text {
                        Picker("Text source", selection: $model.inspectionSource) {
                            ForEach(InspectionSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        fullText
                    } else {
                        Text("− PDF text   + Apple OCR")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        diffText
                    }
                }
                .padding()
            }
            .navigationTitle("Text inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var fullText: some View {
        let pages = model.text.pages(for: model.inspectionSource)
        return ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
            VStack(alignment: .leading, spacing: 8) {
                Text("Page \(index + 1)").font(.headline)
                Text(page.isEmpty ? "No text on this page." : page)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var diffText: some View {
        let count = max(model.text.embedded.count, model.text.ocr.count)
        return ForEach(0..<count, id: \.self) { index in
            let embedded = index < model.text.embedded.count ? model.text.embedded[index] : ""
            let ocr = index < model.text.ocr.count ? model.text.ocr[index] : ""
            let rows = TextDiff.rows(embedded: embedded, ocr: ocr)
            VStack(alignment: .leading, spacing: 6) {
                Text("Page \(index + 1)").font(.headline)
                if rows.isEmpty || rows.allSatisfy({ $0.kind == .unchanged }) {
                    Text("No differences.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        diffLine(row)
                    }
                }
            }
        }
    }

    private func diffLine(_ row: TextDiffRow) -> some View {
        let symbol: String
        let color: Color
        switch row.kind {
        case .unchanged: symbol = " "; color = .secondary
        case .removed: symbol = "−"; color = .red
        case .added: symbol = "+"; color = .green
        }
        return Text("\(symbol) \(row.text)")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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
