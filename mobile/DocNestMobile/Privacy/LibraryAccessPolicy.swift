import Foundation
import Synchronization

/// Shared with the store so background relocking blocks new work synchronously, without an actor hop.
final class LibraryAccessPolicy: Sendable {
    private let locked: Mutex<Bool>
    init(locked: Bool = false) { self.locked = Mutex(locked) }
    var isLocked: Bool { locked.withLock { $0 } }
    func setLocked(_ value: Bool) { locked.withLock { $0 = value } }
    func requireUnlocked() throws { if isLocked { throw LibraryError.libraryLocked } }
}
