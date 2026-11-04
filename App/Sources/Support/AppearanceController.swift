import AppKit
import DropKeeperCore

/// Applies the Auto / Light / Dark setting to the whole app, so windows, the panel and the popover follow it.
enum AppearanceController {
    @MainActor
    static func apply(_ appearance: Appearance) {
        switch appearance {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
