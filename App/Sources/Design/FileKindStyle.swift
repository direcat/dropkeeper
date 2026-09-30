import DropKeeperCore
import SwiftUI

extension FileKind {
    /// Line-style SF Symbol for the file type (design manual §5).
    var symbolName: String {
        switch self {
        case .image: "photo"
        case .document: "doc.richtext"
        case .archive: "archivebox"
        case .installer: "shippingbox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .image: TK.FileType.image
        case .document: TK.FileType.document
        case .archive: TK.FileType.archive
        case .installer: TK.FileType.installer
        case .code: TK.FileType.code
        case .other: TK.FileType.other
        }
    }
}
