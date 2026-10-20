import AppKit
import DropKeeperCore
import QuickLookThumbnailing
import SwiftUI

/// The icon Finder shows for a file: a Quick Look thumbnail when there is one (images, PDFs…), else the type icon.
/// Falls back to the file-kind glyph when the file is gone.
struct FinderIcon: View {
    let path: String
    let kind: FileKind
    var size: CGFloat = TK.Size.fileGlyph
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image = thumbnail ?? FinderIcons.icon(for: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            } else {
                FileGlyph(kind: kind, size: size)
            }
        }
        .task(id: path) {
            thumbnail = await FinderIcons.thumbnail(for: path, size: size, scale: displayScale)
        }
    }
}

/// Caches icons and thumbnails by path; the list re-renders every second while counting down.
@MainActor
enum FinderIcons {
    private static let icons = NSCache<NSString, NSImage>()
    private static let thumbnails = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage? {
        if let cached = icons.object(forKey: path as NSString) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(image, forKey: path as NSString)
        return image
    }

    /// A Finder-style (icon mode) Quick Look thumbnail, generated locally; nil when the file is gone or has none.
    static func thumbnail(for path: String, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = "\(path)#\(Int(size * scale))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path), size: CGSize(width: size, height: size), scale: scale,
            representationTypes: .thumbnail)
        request.iconMode = true
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        thumbnails.setObject(image, forKey: key)
        return image
    }
}
