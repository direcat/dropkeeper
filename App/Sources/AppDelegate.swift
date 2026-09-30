import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    let model = AppDelegate.makeModel()
    private var systemEvents: SystemEvents?
    private var panels: PanelCoordinator?
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private lazy var actions = AppActions(
        openSettings: { [weak self] in
            self?.statusItem?.closePopover()
            self?.openSettings()
        },
        quit: { NSApp.terminate(nil) },
        review: { [weak self] in
            self?.statusItem?.closePopover()
            self?.model.promptRequested = true
        })
    private let log = Logger(subsystem: "net.direcat.dropkeeper", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        installMainMenu()
        Task { await launch() }
    }

    /// Returning from System Settings (e.g. after granting folder access) updates the folder status.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Task { await model.refreshFolders() }
    }

    private func launch() async {
        let bootstrap: EngineBootstrap.Result
        do {
            bootstrap = try EngineBootstrap.make(databaseURL: try Self.databaseURL(), defaults: Self.appDefaults)
        } catch {
            presentFatal(error)
            return
        }
        await model.start(with: bootstrap)
        #if DEBUG
            // Development only: `-watch /path/to/folder` watches a folder before Settings exists. It needs `-dbPath`
            // (and should be run with `-noLoginItem YES`), so a debug run never writes folders or hints into the
            // real database or defaults. Example:
            // DropKeeper -dbPath /tmp/dk/db.sqlite -noLoginItem YES -watch /tmp/dk/Downloads
            if let path = UserDefaults.standard.string(forKey: "watch") {
                if UserDefaults.standard.string(forKey: "dbPath") != nil {
                    await model.addFolder(URL(fileURLWithPath: path))
                } else {
                    log.error("Ignoring -watch without -dbPath")
                }
            }
        #endif
        systemEvents = SystemEvents(
            onWake: { [model] in Task { await model.handleWake() } },
            onClockChange: { [model] in Task { await model.handleClockChange() } })
        didLaunch()
    }

    /// Task 11 adds the onboarding window here.
    private func didLaunch() {
        let status = StatusItemController(model: model, actions: actions)
        statusItem = status
        let panels = PanelCoordinator(
            model: model, actions: actions, statusAnchor: { [weak status] in status?.anchorFrame })
        panels.start()
        self.panels = panels
    }

    private func openSettings() { settingsWindow.show() }

    /// An LSUIElement app has no menu bar, but the key equivalents of its main menu still work in its windows:
    /// ⌘, opens Settings, ⌘W closes, ⌘Q quits, and the Edit items make copy and paste work in text fields.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Quit DropKeeper"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(
            withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func showSettings() { openSettings() }

    private static func makeModel() -> AppModel {
        #if DEBUG
            // Development only: `-noLoginItem YES` never registers this build as a login item.
            if UserDefaults.standard.bool(forKey: "noLoginItem") {
                return AppModel(defaults: appDefaults, applyLoginItem: { _ in })
            }
        #endif
        return AppModel(defaults: appDefaults)
    }

    /// Where the app keeps its own state (folder hints, first-launch markers).
    private static let appDefaults: UserDefaults = {
        #if DEBUG
            // A `-dbPath` run keeps that state in a separate suite, so it never marks the real app as launched
            // or leaves folder hints that would turn its next real launch into a recovery. A new database starts
            // with empty state, like a first launch.
            if let path = UserDefaults.standard.string(forKey: "dbPath"),
                let suite = UserDefaults(suiteName: debugSuiteName)
            {
                if !FileManager.default.fileExists(atPath: path) {
                    suite.removePersistentDomain(forName: debugSuiteName)
                }
                return suite
            }
        #endif
        return .standard
    }()

    #if DEBUG
        private static let debugSuiteName = "net.direcat.dropkeeper.debug"
    #endif

    private static func databaseURL() throws -> URL {
        #if DEBUG
            // Development only: `-dbPath /path/to/db.sqlite` uses a throwaway database.
            if let path = UserDefaults.standard.string(forKey: "dbPath") {
                return URL(fileURLWithPath: path)
            }
        #endif
        return try EngineBootstrap.databaseURL()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningTests else { return .terminateNow }
        Task {
            await model.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func presentFatal(_ error: any Error) {
        log.fault("Cannot open database: \(String(describing: error), privacy: .private)")
        let alert = NSAlert()
        alert.messageText = String(localized: "DropKeeper can't open its database")
        alert.informativeText = String(localized: "Quit DropKeeper and try again. Your files have not been touched.")
        alert.alertStyle = .critical
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}
