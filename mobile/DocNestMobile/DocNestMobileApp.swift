import SwiftUI

@main
struct DocNestMobileApp: App {
    @State private var store: LibraryStore
    @State private var access: LibraryLockController
    @State private var captures: CaptureInbox
    @State private var ready = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var setupError: String?

    init() {
        #if DEBUG
        let root = DevelopmentFixtures.testRoot ?? LibraryStore.defaultRoot
        let defaults = DevelopmentFixtures.testDefaults ?? .standard
        let access = LibraryLockController(defaults: defaults, authenticator: DevelopmentFixtures.testAuthenticator ?? DeviceOwnerAuthenticator())
        let captureRoot = DevelopmentFixtures.testRoot?.appending(path: "CaptureInbox") ?? CaptureInbox.defaultRoot
        #else
        let root = LibraryStore.defaultRoot
        let access = LibraryLockController()
        let captureRoot = CaptureInbox.defaultRoot
        #endif
        _access = State(initialValue: access)
        _store = State(initialValue: LibraryStore(root: root, accessPolicy: access.policy))
        _captures = State(initialValue: CaptureInbox(root: captureRoot, protectedLibraryRoots: [root]))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ready { ContentView(store: store, access: access, captures: captures) }
                else if let setupError { Text(setupError) }
                else { ProgressView("Opening library…") }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: access.activityChanged(.active)
                case .background: access.activityChanged(.background)
                default: access.activityChanged(.inactive)
                }
            }
            .background(PrivacyShield(access: access, activity: access.activity, locked: access.isLocked,
                                      enabled: access.isEnabled, systemTasks: access.systemTaskCount))
            .task {
                guard !ready else { return }
                #if DEBUG
                if let root = DevelopmentFixtures.testRoot {
                    // Fixture seeding is confined to a validated synthetic test root, before opening the protected store.
                    do { try await DevelopmentFixtures.seed(LibraryStore(root: root)) }
                    catch { setupError = error.localizedDescription; return }
                }
                #endif
                ready = true
            }
        }
    }
}
