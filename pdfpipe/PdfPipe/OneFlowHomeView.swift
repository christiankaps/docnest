import SwiftUI
import UniformTypeIdentifiers

struct OneFlowHomeView: View {
    @State private var importing = false
    @State private var session: OneFlowSessionModel?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text("Open a PDF or image")
                    .font(.title2.bold())
                Text("Choose a filename from document dates and suggested words, then share or save the copy.")
                    .font(.body).foregroundStyle(.secondary)
                Button { importing = true } label: {
                    Label("Open a document", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("importDocument")
                Spacer()
                Text("PDF, JPEG or PNG · The original stays unchanged")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Text("Build: \(BuildInfo.displayDate)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("buildDate")
            }
            .padding(24)
            .navigationTitle("PDF Pipe")
            .toolbar {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test document") { openFixture() }.accessibilityIdentifier("openFixture")
                    }
                }
                #endif
            }
            .sheet(isPresented: Binding(get: { session != nil }, set: { _ in })) {
                if let session { OneFlowWorkbenchView(model: session) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png]) { result in
                switch result {
                case .success(let url): open(url)
                case .failure(let failure):
                    let ns = failure as NSError
                    if ns.domain != NSCocoaErrorDomain || ns.code != NSUserCancelledError {
                        error = failure.localizedDescription
                    }
                }
            }
            .onOpenURL { url in
                if session != nil {
                    do { try InboxDelivery.discard(url) } catch { self.error = error.localizedDescription }
                    if error == nil { error = "Finish or discard the current document before opening another." }
                } else { open(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    session?.persistDraft()
                    do { try InboxDelivery.removeUnclaimed() } catch { self.error = error.localizedDescription }
                }
            }
            .task {
                do {
                    try InboxDelivery.excludeFromBackup()
                    let root = try TemporarySession.root()
                    let snapshot: ActiveSessionStore.Snapshot?
                    do { snapshot = try ActiveSessionStore.load(root: root) }
                    catch {
                        try? ActiveSessionStore.clear(root: root)
                        self.error = "The previous document's draft could not be read: \(error.localizedDescription)"
                        snapshot = nil
                    }
                    try TemporarySession.removeAbandoned(root: root)
                    if session == nil, let snapshot {
                        let model = OneFlowSessionModel(recoverable: true)
                        model.onFinished = { session = nil }
                        session = model
                        do { try await model.restore(snapshot) }
                        catch {
                            try? ActiveSessionStore.clear(id: snapshot.id, root: root)
                            model.discard()
                            self.error = "The previous document could not be restored: \(error.localizedDescription)"
                        }
                    }
                } catch { self.error = error.localizedDescription }
            }
            .alert("PDF Pipe", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .tint(PipeAppearance.accent)
    }

    private func open(_ url: URL) {
        let model = OneFlowSessionModel(recoverable: true)
        model.onFinished = { session = nil }
        session = model
        model.importFile(url)
    }

    #if DEBUG
    private func openFixture() {
        do { open(try DevelopmentFixtures.document()) }
        catch { self.error = error.localizedDescription }
    }
    #endif
}
