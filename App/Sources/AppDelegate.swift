import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    let model = AppModel()
    private var systemEvents: SystemEvents?
    private let log = Logger(subsystem: "net.direcat.dropkeeper", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Task { await launch() }
    }

    private func launch() async {
        let bootstrap: EngineBootstrap.Result
        do {
            bootstrap = try EngineBootstrap.make(databaseURL: try EngineBootstrap.databaseURL(), defaults: .standard)
        } catch {
            presentFatal(error)
            return
        }
        await model.start(with: bootstrap)
        #if DEBUG
            // Development only: `-watch /path/to/folder` (scheme argument) watches a folder before Settings exists.
            if let path = UserDefaults.standard.string(forKey: "watch") {
                await model.addFolder(URL(fileURLWithPath: path))
            }
        #endif
        systemEvents = SystemEvents(
            onWake: { [model] in Task { await model.handleWake() } },
            onClockChange: { [model] in Task { await model.handleClockChange() } })
        didLaunch()
    }

    /// Later tasks create the status item, panels and windows here.
    private func didLaunch() {}

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
