import AppKit

/// What "Show in Finder" can do for a tracked path: select the file, open its folder when the file is gone, or
/// nothing when the folder is gone too.
enum FinderReveal {
    enum Target: Equatable {
        case file(String)
        case folder(String)
        case unavailable
    }

    static func target(for path: String, fileExists: (String) -> Bool) -> Target {
        if fileExists(path) { return .file(path) }
        let parent = (path as NSString).deletingLastPathComponent
        return fileExists(parent) ? .folder(parent) : .unavailable
    }

    static func target(for path: String) -> Target {
        target(for: path, fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    @MainActor
    static func reveal(_ target: Target) {
        switch target {
        case .file(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .folder(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .unavailable: break
        }
    }
}
