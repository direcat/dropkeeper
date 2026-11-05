import AppKit
import SwiftUI

/// The window's content: our own tab bar, stretched across the full width (a toolbar's tabs sit centered and
/// can't be stretched), over the glass surface. The selected tab is remembered across launches.
@MainActor
final class SettingsRootController: NSHostingController<SettingsRootView> {
    static let selectedTabKey = "settingsTab"

    let store: SettingsDraft
    private let defaults: UserDefaults

    init(model: AppModel, store: SettingsDraft, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        let saved = defaults.integer(forKey: Self.selectedTabKey)
        store.activeTab = SettingsTab.allCases.indices.contains(saved) ? SettingsTab.allCases[saved] : .general
        // The closure needs `self`, which doesn't exist yet: it reaches the store and defaults directly.
        super.init(
            rootView: SettingsRootView(
                model: model, store: store,
                onSelect: { tab in
                    store.activeTab = tab
                    defaults.set(SettingsTab.allCases.firstIndex(of: tab) ?? 0, forKey: Self.selectedTabKey)
                }))
        // One fixed window size for every tab; content scrolls inside a tab.
        sizingOptions = []
        preferredContentSize = TK.Size.settingsWindow
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
    }

    /// The window, once opened (internal for tests).
    var settingsWindow: NSWindow? { window }

    func show() {
        if let window, !window.isVisible {
            // A fresh view per opening, so a reopened window shows no leftover state (e.g. the cleared-records count).
            window.contentViewController = makeTabs()
            placeOnOpen(window)
        } else if window == nil {
            let window = NSWindow(contentViewController: makeTabs())
            window.title = String(localized: "DropKeeper Settings")
            // The tab bar sits right under the traffic lights, on the glass surface.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            self.window = window
            placeOnOpen(window)
        }
        // An error from elsewhere (e.g. the prompt) would otherwise pop up out of context in Settings.
        model.clearError()
        // Becoming active refreshes the folders (AppDelegate); only an already active app needs it here.
        let wasActive = NSApp.isActive
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if wasActive { Task { await model.refreshFolders() } }
    }

    /// Sized before centering: the tab controller only applies its children's size once they appear, which would
    /// grow the window from its left edge after `center()`. A window that is already visible stays where it is.
    private func placeOnOpen(_ window: NSWindow) {
        window.setContentSize(TK.Size.settingsWindow)
        window.center()
    }

    private func makeTabs() -> NSViewController {
        SettingsRootController(model: model, store: SettingsDraft(model: model), defaults: defaults)
    }
}
