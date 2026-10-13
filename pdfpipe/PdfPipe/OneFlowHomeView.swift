import SwiftUI
import UniformTypeIdentifiers

struct OneFlowHomeView: View {
    @ObservedObject var settings: OneFlowSettingsStore
    @State private var importing = false
    @State private var showingSettings = false
    @State private var session: OneFlowSessionModel?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text("Open a PDF or image")
                    .font(.title2.bold())
                Text("Choose a filename from suggested dates and words, then share or save the copy.")
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
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test document") { openFixture() }.accessibilityIdentifier("openFixture")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingSettings) { OneFlowSettingsView(settings: settings) }
            .sheet(isPresented: Binding(get: { session != nil }, set: { _ in })) {
                if let session { OneFlowWorkbenchView(model: session, settings: settings) }
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
                if phase == .active { settings.reload() }
                if phase == .background {
                    do { try InboxDelivery.removeUnclaimed() } catch { self.error = error.localizedDescription }
                }
            }
            .task {
                do {
                    try InboxDelivery.excludeFromBackup()
                    try TemporarySession.removeAbandoned(root: TemporarySession.root())
                } catch { self.error = error.localizedDescription }
            }
            .alert("PDF Pipe", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .tint(PipeAppearance.accent)
    }

    private func open(_ url: URL) {
        let model = OneFlowSessionModel()
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

private struct OneFlowSettingsView: View {
    @ObservedObject var settings: OneFlowSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let destination = settings.destination {
                        Label(destination.name, systemImage: "folder")
                        Button("Change folder") { choosingFolder = true }
                        Button("Remove folder", role: .destructive) { settings.clear() }
                    } else {
                        Button("Choose a folder") { choosingFolder = true }
                    }
                } header: {
                    Text("Quick save folder")
                } footer: {
                    Text("A folder gives you a one-tap Save action after naming. PDF Pipe never saves automatically.")
                }
                if let settingError = settings.error {
                    Section { Label(settingError, systemImage: "exclamationmark.triangle") }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                do { try settings.choose(result.get()) }
                catch {
                    let ns = error as NSError
                    if ns.domain != NSCocoaErrorDomain || ns.code != NSUserCancelledError {
                        self.error = error.localizedDescription
                    }
                }
            }
            .alert("Cannot choose folder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
