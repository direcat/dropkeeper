import AppKit

/// Brings a window of this menu bar (accessory) app to the front as the key window.
///
/// A single `NSApp.activate()` is not enough when the window opens from the list card: the card is a
/// non-activating panel, and while it closes (and its menu dismisses) AppKit hands the activation back to the
/// previously active app on a later turn, which leaves the new window behind other apps' windows. So the window
/// is brought forward now and once more after the pending close has settled.
@MainActor
enum FrontWindow {
    static func present(
        _ window: NSWindow,
        activate: @escaping @MainActor () -> Void = { NSApp.activate() },
        later: (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    ) {
        bringForward(window, activate: activate)
        later { [weak window] in
            guard let window, window.isVisible else { return }
            bringForward(window, activate: activate)
        }
    }

    private static func bringForward(_ window: NSWindow, activate: @MainActor () -> Void) {
        activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
