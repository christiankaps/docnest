import Foundation
import LocalAuthentication
import Observation

@MainActor
protocol LibraryAuthenticating {
    func authenticate(reason: String) async throws
    func cancel()
}

@MainActor
final class DeviceOwnerAuthenticator: LibraryAuthenticating {
    private var context: LAContext?
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.passcodeNotSet)
        }
        self.context = context
        defer { if self.context === context { self.context = nil } }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
    }
    func cancel() { context?.invalidate(); context = nil }
}

@MainActor @Observable
final class LibraryLockController {
    enum Activity { case active, inactive, background }
    let policy: LibraryAccessPolicy
    private(set) var isEnabled: Bool
    private(set) var isAuthenticating = false
    private(set) var activity: Activity = .active
    private(set) var systemTaskCount = 0
    var authenticationError: String?
    var captureNotice: String?
    private(set) var isLocked: Bool
    @ObservationIgnored var privacyDidChange: (() -> Void)?
    private let defaults: UserDefaults
    private let authenticator: any LibraryAuthenticating
    private var attempt = 0

    init(defaults: UserDefaults = .standard, authenticator: any LibraryAuthenticating = DeviceOwnerAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: "libraryLockEnabled")
        isEnabled = enabled
        isLocked = enabled
        policy = LibraryAccessPolicy(locked: enabled)
    }

    func activityChanged(_ next: Activity) {
        activity = next
        if next == .background {
            if isEnabled { policy.setLocked(true); isLocked = true }
            attempt += 1
            authenticator.cancel()
            isAuthenticating = false
        }
        privacyDidChange?()
    }

    func beginSystemTask() { systemTaskCount += 1; privacyDidChange?() }
    func endSystemTask() { systemTaskCount = max(0, systemTaskCount - 1); privacyDidChange?() }

    @discardableResult
    func unlock() async -> Bool {
        guard isEnabled else { return true }
        guard policy.isLocked else { return true }
        return await authenticate(targetEnabled: true)
    }

    @discardableResult
    func setEnabled(_ value: Bool) async -> Bool {
        guard value != isEnabled else { return true }
        return await authenticate(targetEnabled: value)
    }

    private func authenticate(targetEnabled: Bool) async -> Bool {
        guard !isAuthenticating, activity != .background else { return false }
        attempt += 1
        let generation = attempt
        isAuthenticating = true
        authenticationError = nil
        defer { if attempt == generation { isAuthenticating = false; privacyDidChange?() } }
        do {
            try await authenticator.authenticate(reason: String(localized: "Authenticate to access your private DocNest library."))
            guard attempt == generation, activity != .background else { return false }
            isEnabled = targetEnabled
            defaults.set(targetEnabled, forKey: "libraryLockEnabled")
            policy.setLocked(false)
            isLocked = false
            captureNotice = nil
            privacyDidChange?()
            return true
        } catch {
            guard attempt == generation else { return false }
            authenticationError = (error as? LAError)?.code == .passcodeNotSet
                ? String(localized: "Set an iPhone passcode before enabling the library lock.")
                : String(localized: "Authentication didn’t complete. Try again.")
            return false
        }
    }
}
