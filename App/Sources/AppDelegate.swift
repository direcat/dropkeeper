import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when the process is the host of the unit-test bundle; the app then does not start the engine.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
    }
}
