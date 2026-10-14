import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class OneFlowSessionModel: ObservableObject {
    enum Phase: Equatable { case idle, processing, ready, finished(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var document: SessionDocument?
    @Published private(set) var analysis: DocumentAnalysis = .empty
    @Published private(set) var ocrStatus = ""
    @Published private(set) var progress = ""
    @Published private(set) var progressFraction: Double?
    @Published var composer = FilenameComposer()
    @Published var manualWord = ""
    @Published private(set) var wordVotes: [String: Int] = WordFeedback.load()
    @Published var error: String?
    var onFinished: (() -> Void)?

    private let inboxDirectory: URL
    private var session: TemporarySession?
    private var engine: DocumentEngine?
    private var task: Task<Void, Never>?
    private var importProgress: Progress?
    private var processingDate = Date()
    private var discarding = false
    private var finished = false

    init(inboxDirectory: URL = InboxDelivery.directory) { self.inboxDirectory = inboxDirectory }

    var fallbackDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: processingDate)
    }

    var dateSuggestions: [DateSuggestion] {
        analysis.dates.isEmpty ? [.init(value: fallbackDate, score: 0, isAmbiguous: false)] : analysis.dates
    }

    func importFile(_ url: URL) {
        do {
            let session = try createSession()
            let source = try InboxDelivery.claim(url, into: session.directory, inbox: inboxDirectory)
            phase = .processing
            progress = "Making a temporary copy…"
            progressFraction = nil
            task = Task {
                do {
                    let importer = Task.detached { try DocumentEngine.stage(source, to: session.directory) }
                    let staged = try await withTaskCancellationHandler { try await importer.value } onCancel: { importer.cancel() }
                    try Task.checkCancellation()
                    await process(staged, originalName: url.lastPathComponent)
                } catch { importFailed(error) }
            }
        } catch { importFailed(error) }
    }

    func importProvider(_ provider: NSItemProvider) {
        do {
            let session = try createSession()
            guard let type = [UTType.pdf, .jpeg, .png].first(where: {
                provider.hasItemConformingToTypeIdentifier($0.identifier)
            }) else { throw PipeError.message("Share one PDF, JPEG, or PNG file.") }
            let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .processing
            progress = "Making a temporary copy…"
            progressFraction = nil
            task = Task {
                do {
                    let incoming: (url: URL, name: String) = try await withCheckedThrowingContinuation { continuation in
                        importProgress = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                            if let error { continuation.resume(throwing: error); return }
                            guard let url else {
                                continuation.resume(throwing: PipeError.message("The sharing app did not provide a file."))
                                return
                            }
                            do {
                                let name = suggestedName?.isEmpty == false ? suggestedName! : url.lastPathComponent
                                continuation.resume(returning: (try DocumentEngine.stage(url, to: session.directory), name))
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                    try Task.checkCancellation()
                    await process(incoming.url, originalName: incoming.name)
                } catch { importFailed(error) }
            }
        } catch { importFailed(error) }
    }

    private func createSession() throws -> TemporarySession {
        let root = try TemporarySession.root()
        try TemporarySession.removeAbandoned(root: root)
        let session = try TemporarySession(root: root)
        self.session = session
        engine = DocumentEngine(session: session)
        processingDate = Date()
        return session
    }

    private func process(_ staged: URL, originalName: String) async {
        guard let engine else { return }
        do {
            setProgress("Preparing document…", fraction: nil)
            let imported = try await engine.prepare(staged: staged, originalName: originalName)
            try Task.checkCancellation()
            let result: AutomaticResult
            do {
                result = try await engine.processAutomatically(imported) { [weak self] message, fraction in
                    await self?.setProgress(message, fraction: fraction)
                }
            } catch {
                if error is CancellationError { throw error }
                setProgress("Preparing document…", fraction: nil)
                result = try await engine.readableFallback(imported, reason: error.localizedDescription)
            }
            try Task.checkCancellation()
            guard !discarding else { return }
            document = result.document
            var suggestions = result.analysis
            suggestions.words = WordFeedback.suggestions(from: suggestions.words, votes: wordVotes)
            analysis = suggestions
            ocrStatus = result.status
            progressFraction = nil
            phase = .ready
        } catch { importFailed(error) }
    }

    private func setProgress(_ message: String, fraction: Double?) {
        guard phase == .processing, !discarding else { return }
        progress = message
        progressFraction = fraction
    }

    private func importFailed(_ failure: Error) {
        guard !discarding else { return }
        phase = .idle
        progressFraction = nil
        error = failure is CancellationError ? "Import canceled." : failure.localizedDescription
    }

    func toggleDate(_ value: String) { toggle(id: "date:\(value)", value: value) }
    func toggleWord(_ word: RankedWord) { toggle(id: "word:\(word.id)", value: word.text) }

    func vote(for word: RankedWord) -> WordFeedback.Vote? {
        wordVotes[word.id].flatMap(WordFeedback.Vote.init(rawValue:))
    }

    func setVote(_ vote: WordFeedback.Vote?, for word: RankedWord) {
        do { wordVotes = try WordFeedback.set(vote, for: word) }
        catch { self.error = error.localizedDescription }
    }

    private func toggle(id: String, value: String) {
        var next = composer
        next.toggle(id: id, value: value)
        composer = next
    }

    func addManualWord() {
        let value = manualWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var next = composer
        next.append(value: value)
        composer = next
        manualWord = ""
    }

    func editFilename(_ value: String) {
        var next = composer
        next.editCompleteName(value)
        composer = next
    }

    func undoFilenameEdit() {
        var next = composer
        next.undoEdit()
        composer = next
    }

    func setSeparator(_ value: FilenameComposer.Separator) {
        var next = composer
        next.separator = value
        composer = next
    }

    func prepareExport() async throws -> URL {
        guard phase == .ready, let document, let engine else {
            throw PipeError.message("Wait for the document to finish processing.")
        }
        let filename = try composer.validFilename.get()
        return try await engine.exportCopy(document, named: filename)
    }

    func exported(_ filename: String) {
        do {
            try cleanSession()
            phase = .finished(filename)
            finishOnce()
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

    private func cleanSession() throws {
        try session?.cleanup()
        session = nil
        engine = nil
        importProgress = nil
        document = nil
        analysis = .empty
    }

    private func finishOnce() {
        guard !finished else { return }
        finished = true
        onFinished?()
    }
}
