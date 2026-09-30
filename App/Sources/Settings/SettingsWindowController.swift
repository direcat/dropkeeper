import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window, !window.isVisible {
            // A fresh view per opening, so a reopened window shows no leftover state (e.g. the cleared-records count).
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = String(localized: "DropKeeper Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An error from elsewhere (e.g. the prompt) would otherwise pop up out of context in Settings.
        model.clearError()
        // Becoming active refreshes the folders (AppDelegate); only an already active app needs it here.
        let wasActive = NSApp.isActive
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if wasActive { Task { await model.refreshFolders() } }
    }
}
