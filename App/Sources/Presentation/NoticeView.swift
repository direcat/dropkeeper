import DropKeeperCore
import SwiftUI

/// "Moved to Trash" notice with Undo (design manual §7.6).
struct NoticeView: View {
    let files: [TrackedFile]
    let canUndo: Bool
    let onUndo: () -> Void
    /// The model clears the files when the notice ends, while the panel still fades out; keep the last ones.
    @State private var lastFiles: [TrackedFile] = []

    private var shown: [TrackedFile] { files.isEmpty ? lastFiles : files }

    nonisolated static func title(for files: [TrackedFile]) -> String {
        files.count == 1 ? files[0].displayName : String(localized: "\(files.count) files")
    }

    var body: some View {
        GlassCard(radius: TK.Radius.compactCard) {
            HStack(spacing: TK.Space.m) {
                // The file is already in the Trash, so its icon comes from there (permanent deletes keep the glyph).
                FinderIcon(path: shown.first?.trashPath ?? "", kind: shown.first?.kind ?? .other)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(for: shown))
                        .font(.system(size: TK.TextSize.title, weight: .semibold))
                        .strikethrough()
                        .foregroundStyle(TK.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    (canUndo ? Text("Moved to Trash") : Text("Deleted"))
                        .font(.system(size: TK.TextSize.small))
                        .foregroundStyle(TK.Palette.textSecondary)
                }
                Spacer()
                if canUndo {
                    Button(action: onUndo) { Text("Undo") }
                        .buttonStyle(PanelTextButtonStyle(tint: TK.Palette.accentText))
                        .focusable(false)
                }
            }
            .padding(.horizontal, TK.Space.l)
            .padding(.vertical, TK.Space.m)
            .frame(width: TK.Size.panelWidth)
        }
        .onChange(of: files, initial: true) { _, new in
            if !new.isEmpty { lastFiles = new }
        }
    }
}

#Preview {
    let now = Date()
    let file = TrackedFile(
        id: "preview", folderId: 1, path: "/tmp/Installer.dmg", inode: 1, volumeId: "V",
        displayName: "Installer.dmg", kind: .installer, sizeBytes: 84_000_000, state: .trashed,
        firstSeen: now, expiresAt: now, trashPath: "/tmp/.Trash/Installer.dmg", failureCount: 0, updatedAt: now)
    NoticeView(files: [file], canUndo: true, onUndo: {})
}
