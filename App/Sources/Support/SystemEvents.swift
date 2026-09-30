import AppKit

/// Forwards wake-from-sleep and system clock changes. Lives for the whole process, so it never removes its observers.
@MainActor
final class SystemEvents {
    private var tokens: [NSObjectProtocol] = []

    init(onWake: @escaping @MainActor () -> Void, onClockChange: @escaping @MainActor () -> Void) {
        tokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { onWake() } })
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { onClockChange() } })
    }
}
