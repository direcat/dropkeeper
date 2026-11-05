import AppKit

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
