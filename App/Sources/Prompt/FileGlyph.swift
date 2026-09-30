import DropKeeperCore
import SwiftUI

struct FileGlyph: View {
    let kind: FileKind
    var size: CGFloat = TK.Size.fileGlyph

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.45, weight: .light))
            .foregroundStyle(kind.tint)
            .frame(width: size, height: size)
            .background(
                kind.tint.opacity(TK.FileType.backgroundOpacity),
                in: RoundedRectangle(cornerRadius: TK.Radius.fileGlyph)
            )
            .accessibilityHidden(true)
    }
}
