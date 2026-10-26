import AppKit
import Foundation

/// Confirmation before a file is deleted permanently from the list or a reminder.
enum DeleteConfirmation {
    @MainActor
    static func confirm(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(name)” permanently?")
        alert.informativeText = String(localized: "This can't be undone.")
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: String(localized: "Delete permanently"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
