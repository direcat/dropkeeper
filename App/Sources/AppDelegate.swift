import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set before terminating to open a new instance of the app once the engine has stopped (language change).
    static var relaunchOnQuit = false
    /// Set while a quit is waiting for the engine to stop, so a second quit cannot start another shutdown.
    private var isTerminating = false

    let model = AppDelegate.makeModel()
    private var systemEvents: SystemEvents?
    private var panels: PanelCoordinator?
    private var statusItem: StatusItemController?
    private lazy var onboarding = OnboardingWindowController(model: model)
    private lazy var settingsWindow = SettingsWindowController(model: model, defaults: AppDelegate.appDefaults)
    private lazy var actions = AppActions(
        openSettings: { [weak self] in
            self?.statusItem?.closePopover()
            self?.openSettings()
        },
        quit: { NSApp.terminate(nil) },
        review: { [weak self] id in
            self?.statusItem?.closePopover()
            self?.model.review(id)
        })
    private let log = Logger(subsystem: "net.direcat.dropkeeper", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        _ = AppLanguage.shared
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
            log.fault("Cannot open database: \(String(describing: error), privacy: .private)")
            presentFatal(String(localized: "DropKeeper can't open its database"))
            return
        }
        // A failed start must not look like a working app: nothing would be watched or trashed.
        guard await model.start(with: bootstrap) else {
            log.fault("Engine failed to start")
            presentFatal(String(localized: "DropKeeper can't start"))
            return
        }
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

    private func didLaunch() {
        let status = StatusItemController(model: model, actions: actions)
        statusItem = status
        let panels = PanelCoordinator(
            model: model, actions: actions, statusAnchor: { [weak status] in status?.anchorFrame },
            isPopoverShown: { [weak status] in status?.isPopoverShown ?? false })
        status.onPopoverChange = { [weak panels] in panels?.render() }
        panels.start()
        self.panels = panels
        if model.needsOnboarding { onboarding.show() }
    }

    private func openSettings() { settingsWindow.show() }

    /// An LSUIElement app has no menu bar, but the key equivalents of its main menu still work in its windows:
    /// ⌘, opens Settings, ⌘W closes, ⌘Q quits, and the Edit items make copy and paste work in text fields.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Settings"), action: #selector(showSettings), keyEquivalent: ",")
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
            // with empty state, like a first launch. The suite name must differ from the Debug bundle id, because
            // `UserDefaults(suiteName:)` refuses the app's own domain.
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
        private static let debugSuiteName = "net.direcat.dropkeeper.debug.dbpath"
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
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        let relaunch = Self.relaunchOnQuit
        Self.relaunchOnQuit = false
        Task {
            await model.stop()
            // The engine is stopped first, so two instances never use the database at the same time.
            if relaunch { await Self.relaunch() }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func relaunch() async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        do {
            try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        } catch {
            Logger(subsystem: "net.direcat.dropkeeper", category: "app")
                .error("Relaunch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(localized: "Quit DropKeeper and try again. Your files have not been touched.")
        alert.alertStyle = .critical
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}
