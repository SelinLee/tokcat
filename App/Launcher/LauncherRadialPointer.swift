import AppKit

/// Owns and balances the process-wide cursor association, including termination.
@MainActor
final class LauncherRadialPointer {
    private(set) var isLocked = false
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.unlock() } }
    }

    func lock() -> Bool {
        guard !isLocked else { return true }
        guard CGAssociateMouseAndMouseCursorPosition(0) == .success else { return false }
        isLocked = true
        return true
    }

    func unlock() {
        guard isLocked else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        isLocked = false
    }

    deinit {
        if isLocked { CGAssociateMouseAndMouseCursorPosition(1) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }
}
