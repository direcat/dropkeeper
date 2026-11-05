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

/// Activates this menu bar app. The cooperative `NSApp.activate()` of macOS 14+ is ignored while another app is
/// frontmost and has not yielded (an accessory app opened from its status item never gets that yield), which left
/// Settings visible but inactive: grey traffic lights, disabled controls. Forcing it is what a menu bar app needs
/// when the user has just asked for one of its windows.
@MainActor
enum AppActivation {
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
