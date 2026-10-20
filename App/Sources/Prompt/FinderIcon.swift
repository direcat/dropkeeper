import AppKit
import DropKeeperCore
import SwiftUI

/// The icon Finder shows for a file, falling back to the file-kind glyph when the file is gone.
struct FinderIcon: View {
    let path: String
    let kind: FileKind
    var size: CGFloat = TK.Size.fileGlyph

    var body: some View {
        if let image = FinderIcons.icon(for: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            FileGlyph(kind: kind, size: size)
        }
    }
}

/// Caches Finder icons by path; the list re-renders every second while counting down.
@MainActor
enum FinderIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
