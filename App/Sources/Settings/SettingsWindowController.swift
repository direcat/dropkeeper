import AppKit
import SwiftUI

/// Toolbar-style tabs. They are AppKit's: a SwiftUI `TabView` in this plain window would draw an in-content
/// segmented control, and the Safari-style toolbar look only comes with a SwiftUI `Settings` scene.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    static let selectedTabKey = "settingsTab"

    private let store: SettingsDraft
    private let defaults: UserDefaults

    init(model: AppModel, store: SettingsDraft, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: SettingsTabView(tab: tab, model: model, store: store))
            // One fixed window size for every tab; content scrolls inside a tab.
            hosting.sizingOptions = []
            hosting.preferredContentSize = TK.Size.settingsWindow
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
            addTabViewItem(item)
        }
        let saved = defaults.integer(forKey: Self.selectedTabKey)
        selectedTabViewItemIndex = tabViewItems.indices.contains(saved) ? saved : 0
        syncActiveTab()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        defaults.set(selectedTabViewItemIndex, forKey: Self.selectedTabKey)
        syncActiveTab()
    }

    private func syncActiveTab() {
        if SettingsTab.allCases.indices.contains(selectedTabViewItemIndex) {
            store.activeTab = SettingsTab.allCases[selectedTabViewItemIndex]
        }
    }
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

    func show() {
        if let window, !window.isVisible {
            // A fresh view per opening, so a reopened window shows no leftover state (e.g. the cleared-records count).
            window.contentViewController = makeTabs()
        }
        if window == nil {
            let window = NSWindow(contentViewController: makeTabs())
            window.title = String(localized: "DropKeeper Settings")
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.center()
        // An error from elsewhere (e.g. the prompt) would otherwise pop up out of context in Settings.
        model.clearError()
        // Becoming active refreshes the folders (AppDelegate); only an already active app needs it here.
        let wasActive = NSApp.isActive
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if wasActive { Task { await model.refreshFolders() } }
    }

    private func makeTabs() -> NSTabViewController {
        SettingsTabViewController(model: model, store: SettingsDraft(model: model), defaults: defaults)
    }
}
