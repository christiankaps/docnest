import SwiftUI

@main
struct DocNestMobileApp: App {
    @State private var store: LibraryStore
    @State private var ready = false
    @State private var setupError: String?

    init() {
        #if DEBUG
        _store = State(initialValue: LibraryStore(root: DevelopmentFixtures.testRoot ?? LibraryStore.defaultRoot))
        #else
        _store = State(initialValue: LibraryStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ready { ContentView(store: store) }
                else if let setupError { Text(setupError) }
                else { ProgressView("Opening library…") }
            }
            .task {
                guard !ready else { return }
                #if DEBUG
                if DevelopmentFixtures.testRoot != nil {
                    do { try await DevelopmentFixtures.seed(store) }
                    catch { setupError = error.localizedDescription; return }
                }
                #endif
                ready = true
            }
        }
    }
}
