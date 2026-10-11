import SwiftUI

struct LibraryLockCover: View {
    let access: LibraryLockController
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield").font(.largeTitle).accessibilityIdentifier("libraryPrivacyCover")
                Text("DocNest").font(.largeTitle.bold())
                if access.activity == .active && access.isLocked {
                    Text("Your library is locked.").foregroundStyle(.secondary)
                    if let notice = access.captureNotice { Text(notice).font(.subheadline) }
                    if let error = access.authenticationError { Text(error).font(.subheadline) }
                    Button("Unlock Library", systemImage: "faceid") { Task { await access.unlock() } }
                        .buttonStyle(.borderedProminent).disabled(access.isAuthenticating)
                        .accessibilityIdentifier("unlockLibrary")
                    if access.isAuthenticating { ProgressView("Authenticating…") }
                }
            }
            .padding().frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

/// A UIKit cover is placed synchronously on scene deactivation, before SwiftUI's next render or snapshot.
struct PrivacyShield: UIViewRepresentable {
    let access: LibraryLockController
    let activity: LibraryLockController.Activity
    let locked: Bool
    let enabled: Bool
    let systemTasks: Int
    func makeUIView(context: Context) -> ShieldAnchor { ShieldAnchor(access: access) }
    func updateUIView(_ view: ShieldAnchor, context: Context) { view.refresh() }
    static func dismantleUIView(_ view: ShieldAnchor, coordinator: ()) { view.dispose() }
}

final class ShieldAnchor: UIView {
    private let access: LibraryLockController
    private let cover: UIHostingController<LibraryLockCover>
    private weak var coveredRoot: UIView?
    private weak var protectedWindow: UIWindow?
    private weak var scene: UIWindowScene?
    init(access: LibraryLockController) {
        self.access = access
        cover = UIHostingController(rootView: LibraryLockCover(access: access))
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        cover.view.backgroundColor = .systemBackground
        cover.view.isOpaque = true
        NotificationCenter.default.addObserver(self, selector: #selector(inactive), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIScene.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIScene.willEnterForegroundNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            protectedWindow = window
            scene = window.windowScene
            switch scene?.activationState {
            case .background: access.activityChanged(.background)
            case .foregroundInactive: access.activityChanged(.inactive)
            default: access.activityChanged(.active)
            }
            access.privacyDidChange = { [weak self] in self?.refresh() }
            refresh()
        }
    }
    private func matches(_ note: Notification) -> Bool {
        guard let scene else { return false }
        return (note.object as? UIWindowScene) === scene
    }
    @objc private func inactive(_ note: Notification) { if matches(note) { access.activityChanged(.inactive) } }
    @objc private func background(_ note: Notification) { if matches(note) { access.activityChanged(.background) } }
    @objc private func active(_ note: Notification) { if matches(note) { access.activityChanged(.active) } }
    @objc private func foreground(_ note: Notification) { if matches(note) { access.activityChanged(.inactive) } }

    func dispose() {
        access.privacyDidChange = nil
        cover.view.removeFromSuperview()
        coveredRoot?.accessibilityElementsHidden = false
        protectedWindow?.accessibilityElements = nil
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        guard let window = protectedWindow, let root = window.rootViewController?.view else { return }
        let visible = access.isEnabled && (access.activity != .active || access.isLocked)
        coveredRoot = root
        root.accessibilityElementsHidden = visible
        guard visible else { window.accessibilityElements = nil; cover.view.removeFromSuperview(); return }
        // While an explicitly registered system task is active, protect the app beneath its native presentation.
        // Background/inactive snapshots always cover the entire window, including pending presentations.
        let container: UIView = access.activity == .active && access.systemTaskCount > 0 ? root : window
        if cover.view.superview !== container { container.addSubview(cover.view) }
        cover.view.frame = container.bounds
        cover.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.view.isUserInteractionEnabled = true
        cover.view.accessibilityViewIsModal = container === window
        window.accessibilityElements = container === window ? [cover.view!] : nil
        container.bringSubviewToFront(cover.view)
        cover.view.layoutIfNeeded()
    }
}

private struct LibrarySystemTask: ViewModifier {
    let access: LibraryLockController?
    let active: Bool
    @State private var registered = false
    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, value in
                if value && !registered { registered = true; access?.beginSystemTask() }
                else if !value && registered { registered = false; access?.endSystemTask() }
            }
            .onDisappear { if registered { registered = false; access?.endSystemTask() } }
    }
}

extension View {
    func librarySystemTask(_ access: LibraryLockController?, active: Bool) -> some View {
        modifier(LibrarySystemTask(access: access, active: active))
    }
}
