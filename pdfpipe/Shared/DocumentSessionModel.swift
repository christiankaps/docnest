import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentSessionModel: ObservableObject {
    @Published var document: ProcessedDocument?
    @Published var pipelineID: UUID?
    @Published var manualText = ""
    @Published var filename = ""
    @Published var progress = ""
    @Published var error: String?
    @Published var busy = false
    @Published var processed = false
    @Published var savedName: String?
    private var session: TemporarySession?
    private var engine: DocumentEngine?
    private var task: Task<Void, Never>?
    private var importProgress: Progress?
    private var finished = false
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

    func importFile(_ url: URL, store: PipelineStore, autoRun: Bool) {
        do {
            let session = try createSession()
            let source = try InboxDelivery.claim(url, into: session.directory, inbox: inboxDirectory)
            busy = true
            progress = "Making a temporary copy…"
            task = Task {
                do {
                    let importer = Task.detached { try DocumentEngine.stage(source, to: session.directory) }
                    let staged = try await withTaskCancellationHandler { try await importer.value } onCancel: { importer.cancel() }
                    try Task.checkCancellation()
                    await prepare(staged, originalName: url.lastPathComponent, store: store, autoRun: autoRun)
                } catch {
                    busy = false
                    self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func importProvider(_ provider: NSItemProvider, store: PipelineStore) {
        do {
            let session = try createSession()
            guard let type = [UTType.pdf, .jpeg, .png].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
                throw PipeError.message("Share a single PDF, JPEG, or PNG file.")
            }
            let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            busy = true
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
                    await prepare(incoming.url, originalName: incoming.name, store: store, autoRun: true)
                } catch {
                    busy = false
                    self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func prepare(_ staged: URL, originalName: String, store: PipelineStore, autoRun: Bool) async {
        guard let engine else { return }
        do {
            document = try await engine.prepare(staged: staged, originalName: originalName)
            filename = document?.facts.filename ?? ""
            busy = false
            if let error = store.error { throw PipeError.message(error) }
            if autoRun, let pipeline = try store.configuration.defaultPipeline() {
                pipelineID = pipeline.id
                await execute(pipeline)
            }
        } catch {
            busy = false
            self.error = error is CancellationError ? "Import canceled." : error.localizedDescription
        }
    }

    func run(_ pipeline: Pipeline) {
        guard !busy else { return }
        busy = true
        task = Task { await execute(pipeline) }
    }

    private func execute(_ pipeline: Pipeline) async {
        guard let engine else { return }
        busy = true
        processed = false
        savedName = nil
        do {
            let result = try await engine.process(pipeline, text: manualText) { [weak self] value in
                await self?.updateProgress(value)
            }
            try Task.checkCancellation()
            document = result
            filename = result.facts.filename
            processed = true
            if pipeline.unattended, let destination = pipeline.destination {
                progress = "Saving to \(destination.name)…"
                // Cancellation must reach the writing task, not just its parent.
                let writer = Task.detached { try DestinationWriter.save(result.url, destination: destination) }
                let saved = try await withTaskCancellationHandler { try await writer.value } onCancel: { writer.cancel() }
                savedName = saved.lastPathComponent
                try cleanSession()
                busy = false
                finishOnce()
            } else { busy = false }
        } catch {
            busy = false
            self.error = error is CancellationError ? "Processing canceled. You can retry or discard the copy." : error.localizedDescription
        }
    }

    private func updateProgress(_ value: String) { progress = value }

    func filenamePreview(_ pipeline: Pipeline, date: Date = Date()) -> Result<String, Error> {
        Result {
            guard let document else { throw PipeError.message("Import a document first.") }
            return try pipeline.outputFilename(original: document.facts.originalBasename, text: manualText, date: date)
        }
    }

    func applyFilename() async throws {
        guard let document, let engine else { return }
        self.document = try await engine.renameResult(document, name: filename)
        filename = self.document?.facts.filename ?? filename
    }

    func save(_ destination: Destination) {
        guard !busy else { return }
        busy = true
        task = Task {
            do {
                try await applyFilename()
                guard let document else { throw PipeError.message("No result is available to save.") }
                progress = "Saving to \(destination.name)…"
                let writer = Task.detached { try DestinationWriter.save(document.url, destination: destination) }
                let saved = try await withTaskCancellationHandler { try await writer.value } onCancel: { writer.cancel() }
                savedName = saved.lastPathComponent
                try cleanSession()
                busy = false
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }

    func exported(_ filename: String) {
        savedName = filename
        do { try cleanSession() } catch { self.error = "Export finished, but temporary cleanup failed: \(error.localizedDescription)" }
    }

    func cancelProcessing() { task?.cancel(); importProgress?.cancel() }

    func discard() {
        let running = task
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
        document = nil
        engine = nil
        importProgress = nil
        session = nil
    }
}
