import AppKit

/// Brings a window of this menu bar (accessory) app to the front as the key window.
///
/// The app is activated with `AppActivation` (a plain cooperative activation is ignored for a menu bar app), now and
/// once more on the next main-queue turn: when the window opens from the list card, closing the card and dismissing
/// its menu can still change the frontmost app after the first call, so the window is brought forward again.
@MainActor
enum FrontWindow {
    static func present(
        _ window: NSWindow,
        activate: @escaping @MainActor () -> Void = { AppActivation.activate() },
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
