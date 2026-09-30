import ServiceManagement
import os

enum LoginItem {
    private static let log = Logger(subsystem: "net.direcat.dropkeeper", category: "login-item")

    @MainActor
    static func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
