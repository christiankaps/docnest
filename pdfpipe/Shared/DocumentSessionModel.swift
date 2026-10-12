import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentSessionModel: ObservableObject {
    enum Phase {
        case idle
        case working(SessionDocument?)
        case review(SessionDocument)
        case naming(SessionDocument)
        case saving(SessionDocument)
        case result(SessionDocument)
        case finished(String)
    }

    @Published private(set) var phase: Phase = .idle
    var document: SessionDocument? {
        switch phase {
        case .working(let document): document
        case .review(let document), .naming(let document), .saving(let document), .result(let document): document
        case .idle, .finished: nil
        }
    }
    var busy: Bool {
        switch phase { case .working, .saving: true; default: false }
    }
    var processed: Bool {
        switch phase { case .result, .saving: true; default: false }
    }
    var awaitingNaming: Bool { if case .naming = phase { true } else { false } }
    var savedName: String? { if case .finished(let name) = phase { name } else { nil } }
    @Published var pipelineID: UUID?
    @Published var manualText = ""
    @Published var filename = ""
    @Published private(set) var progress = ""
    @Published var error: String?
    @Published private(set) var analysis: DocumentAnalysis?
    @Published private(set) var selectedWords: [String] = []
    @Published var selectedDate: String?
    @Published var manualKeyword = ""
    private var session: TemporarySession?
    private var engine: DocumentEngine?
    private var task: Task<Void, Never>?
    private var importProgress: Progress?
    private var finished = false
    private var discarding = false
    private var runDate: Date?
    private var pendingRun: PreparedRun?
    private var pendingPipeline: Pipeline?
    private let inboxDirectory: URL
    var onFinished: (() -> Void)?

    init(inboxDirectory: URL = InboxDelivery.directory) {
        self.inboxDirectory = inboxDirectory
    }

    func createSession() throws -> TemporarySession {
        let root = try TemporarySession.root()
        try TemporarySession.removeAbandoned(root: root)
        let session = try TemporarySession(root: root)
        self.session = session
        engine = DocumentEngine(session: session)
        return session
    }

    func importFile(_ url: URL, snapshot: PipelineImportSnapshot, autoRun: Bool) {
        do {
            let session = try createSession()
            let source = try InboxDelivery.claim(url, into: session.directory, inbox: inboxDirectory)
            phase = .working(nil)
            progress = "Making a temporary copy…"
            task = Task {
                do {
                    let importer = Task.detached { try DocumentEngine.stage(source, to: session.directory) }
                    let staged = try await withTaskCancellationHandler { try await importer.value } onCancel: { importer.cancel() }
                    try Task.checkCancellation()
                    await prepare(staged, originalName: url.lastPathComponent, snapshot: snapshot, autoRun: autoRun)
                } catch {
                    guard !discarding else { return }
                    phase = .idle
                    self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func importProvider(_ provider: NSItemProvider, snapshot: PipelineImportSnapshot) {
        do {
            let session = try createSession()
            guard let type = [UTType.pdf, .jpeg, .png].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
                throw PipeError.message("Share a single PDF, JPEG, or PNG file.")
            }
            let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .working(nil)
            progress = "Making a temporary copy…"
            task = Task {
                do {
                    let incoming: (url: URL, name: String) = try await withCheckedThrowingContinuation { continuation in
                        importProgress = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                            if let error { continuation.resume(throwing: error); return }
                            guard let url else { continuation.resume(throwing: PipeError.message("The sharing app did not provide a file.")); return }
                            do {
                                let originalName = (suggestedName?.isEmpty == false ? suggestedName! : url.lastPathComponent)
                                continuation.resume(returning: (try DocumentEngine.stage(url, to: session.directory), originalName))
                            }
                            catch { continuation.resume(throwing: error) }
                        }
                    }
                    try Task.checkCancellation()
                    await prepare(incoming.url, originalName: incoming.name, snapshot: snapshot, autoRun: true)
                } catch {
                    guard !discarding else { return }
                    phase = .idle
                    self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func prepare(_ staged: URL, originalName: String, snapshot: PipelineImportSnapshot, autoRun: Bool) async {
        guard let engine else { return }
        do {
            let prepared = try await engine.prepare(staged: staged, originalName: originalName)
            try Task.checkCancellation()
            filename = prepared.facts.filename
            phase = .review(prepared)
            if let error = snapshot.error { throw PipeError.message(error) }
            if autoRun, let pipeline = try snapshot.configuration.defaultPipeline() {
                pipelineID = pipeline.id
                await execute(pipeline)
            }
        } catch {
            guard !discarding else { return }
            if case .working = phase { phase = .idle }
            self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
        }
    }

    func run(_ pipeline: Pipeline) {
        guard case .review(let document) = phase else { return }
        phase = .working(document)
        runDate = Date()
        task = Task { await execute(pipeline) }
    }

    private func execute(_ pipeline: Pipeline) async {
        guard let engine else { return }
        let previous = document
        phase = .working(previous)
        analysis = nil
        selectedWords = []
        selectedDate = nil
        pendingRun = nil
        pendingPipeline = nil
        do {
            let date = runDate ?? Date()
            runDate = date
            let prepared = try await engine.prepareRun(pipeline, text: manualText, date: date) { [weak self] value in
                await self?.updateProgress(value)
            }
            try Task.checkCancellation()
            if pipeline.needsAnalysis && !pipeline.unattended {
                let preview = try await engine.preview(prepared)
                pendingRun = prepared
                pendingPipeline = pipeline
                analysis = prepared.analysis
                phase = .naming(preview)
                progress = "Choose a filename"
                return
            }
            let values = namingValues(for: prepared)
            if pipeline.needsAnalysis && pipeline.unattended {
                do { _ = try pipeline.outputFilename(values: values) }
                catch {
                    let preview = try await engine.preview(prepared)
                    pendingRun = prepared
                    pendingPipeline = pipeline
                    analysis = prepared.analysis
                    phase = .naming(preview)
                    self.error = "Automatic naming needs review: \(error.localizedDescription)"
                    return
                }
            }
            let result = try await engine.finishRun(prepared, pipeline: pipeline, values: values)
            try Task.checkCancellation()
            filename = result.facts.filename
            if pipeline.unattended, let destination = pipeline.destination {
                phase = .saving(result)
                progress = "Saving to \(destination.name)…"
                let writer = Task.detached { try DestinationWriter.save(result.url, destination: destination) }
                let saved = try await withTaskCancellationHandler { try await writer.value } onCancel: { writer.cancel() }
                try Task.checkCancellation()
                try cleanSession()
                phase = .finished(saved.lastPathComponent)
                finishOnce()
            } else { phase = .result(result) }
        } catch {
            guard !discarding else { return }
            switch phase {
            case .saving(let document): phase = .result(document)
            case .working: phase = previous.map { .review($0) } ?? .idle
            default: break
            }
            self.error = error is CancellationError ? "Processing canceled. You can retry or discard the copy." : error.localizedDescription
        }
    }

    private func namingValues(for prepared: PreparedRun) -> NamingValues {
        NamingValues(original: document?.facts.originalBasename ?? "Document", manualText: manualText,
            processedAt: prepared.processedAt, documentDate: selectedDate ?? prepared.analysis.date.value,
            dateAmbiguous: prepared.analysis.date.isAmbiguous && selectedDate == nil,
            words: prepared.analysis.words.map(\.text))
    }

    func selectedFilenamePreview() -> Result<String, Error> {
        Result {
            guard let pendingRun, let pendingPipeline else { throw PipeError.message("Analyze a document first.") }
            if !selectedWords.isEmpty {
                let values = namingValues(for: pendingRun)
                let date = try FilenameTemplate.render("{documentDate}", values: values)
                let stem = String(date.dropLast(4)) + "_" + selectedWords.joined(separator: "_")
                return try FilenameTemplate.filename(stem)
            }
            return try pendingPipeline.outputFilename(values: namingValues(for: pendingRun))
        }
    }

    func toggleWord(_ word: String) {
        if let index = selectedWords.firstIndex(of: word) { selectedWords.remove(at: index) }
        else { selectedWords.append(word) }
    }

    func addManualKeyword() {
        let term = manualKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !selectedWords.contains(term) else { return }
        selectedWords.append(term)
        manualKeyword = ""
    }

    func resetNaming() {
        guard case .naming(let document) = phase else { return }
        phase = .review(document)
        pendingRun = nil
        pendingPipeline = nil
        analysis = nil
        selectedWords = []
        selectedDate = nil
    }

    func confirmNaming() {
        guard case .naming(let document) = phase,
              let pendingRun, let pendingPipeline, let engine else { return }
        phase = .working(document)
        task = Task {
            do {
                let resolved = try selectedFilenamePreview().get()
                let final = try await engine.finishRun(pendingRun, pipeline: pendingPipeline,
                    values: namingValues(for: pendingRun), overrideFilename: selectedWords.isEmpty ? nil : resolved)
                try Task.checkCancellation()
                phase = .result(final)
                filename = final.facts.filename
                self.pendingRun = nil
                self.pendingPipeline = nil
            } catch {
                guard !discarding else { return }
                if case .working(let document) = phase, let document { phase = .naming(document) }
                self.error = error.localizedDescription
            }
        }
    }

    private func updateProgress(_ value: String) { progress = value }

    func filenamePreview(_ pipeline: Pipeline, date: Date = Date()) -> Result<String, Error> {
        Result {
            guard let document else { throw PipeError.message("Import a document first.") }
            if pipeline.needsAnalysis { return "Filename available after document analysis" }
            return try pipeline.outputFilename(original: document.facts.originalBasename, text: manualText,
                date: runDate ?? date)
        }
    }

    func applyFilename() async throws {
        guard let document, let engine else { return }
        let renamed = try await engine.renameResult(document, name: filename)
        guard !discarding else { throw CancellationError() }
        if case .saving = phase { phase = .saving(renamed) }
        else { phase = .result(renamed) }
        filename = renamed.facts.filename
    }

    func save(_ destination: Destination) {
        guard case .result(let document) = phase else { return }
        phase = .saving(document)
        task = Task {
            do {
                try await applyFilename()
                guard let document = self.document else { throw PipeError.message("No result is available to save.") }
                progress = "Saving to \(destination.name)…"
                let writer = Task.detached { try DestinationWriter.save(document.url, destination: destination) }
                let saved = try await withTaskCancellationHandler { try await writer.value } onCancel: { writer.cancel() }
                try Task.checkCancellation()
                try cleanSession()
                phase = .finished(saved.lastPathComponent)
            } catch {
                guard !discarding else { return }
                if case .saving(let document) = phase { phase = .result(document) }
                self.error = error.localizedDescription
            }
        }
    }

    func exported(_ filename: String) {
        do {
            try cleanSession()
            phase = .finished(filename)
        } catch { self.error = "Export finished, but temporary cleanup failed: \(error.localizedDescription)" }
    }

    func cancelProcessing() { task?.cancel(); importProgress?.cancel() }

    func discard() {
        guard !discarding else { return }
        discarding = true
        let running = task
        phase = .idle
        running?.cancel()
        importProgress?.cancel()
        task = Task {
            await running?.value
            do { try cleanSession(); finishOnce() }
            catch { self.error = "Cannot remove the temporary copy: \(error.localizedDescription)" }
        }
    }

    private func finishOnce() {
        guard !finished else { return }
        finished = true
        onFinished?()
    }

    private func cleanSession() throws {
        try session?.cleanup()
        phase = .idle
        engine = nil
        importProgress = nil
        session = nil
    }
}
