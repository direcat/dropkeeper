import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let downloads = OnboardingFolder.target(
            downloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
            dbPath: UserDefaults.standard.string(forKey: "dbPath"),
            watch: UserDefaults.standard.string(forKey: "watch"))
        let view = OnboardingView(model: model, downloads: downloads) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Welcome to DropKeeper")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// The folder onboarding offers to watch.
enum OnboardingFolder {
    /// A safe debug run (`-dbPath` with `-watch`, see AppDelegate) offers its test folder, which it already
    /// watches, so it never asks for the real Downloads. Release builds always use Downloads.
    static func target(downloads: URL, dbPath: String?, watch: String?) -> URL {
        #if DEBUG
            if dbPath != nil, let watch { return URL(fileURLWithPath: watch) }
        #endif
        return downloads
    }
}
