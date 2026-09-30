import DropKeeperCore
import SwiftUI

/// "Moved to Trash" notice with Undo (design manual §7.6).
struct NoticeView: View {
    let files: [TrackedFile]
    let canUndo: Bool
    let onUndo: () -> Void

    nonisolated static func title(for files: [TrackedFile]) -> String {
        files.count == 1 ? files[0].displayName : String(localized: "\(files.count) files")
    }

    var body: some View {
        HStack(spacing: TK.Space.m) {
            FileGlyph(kind: files.first?.kind ?? .other)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: files))
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough()
                    .foregroundStyle(TK.Notch.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                (canUndo ? Text("Moved to Trash") : Text("Deleted"))
                    .font(.system(size: 11))
                    .foregroundStyle(TK.Notch.textPrimary)
            }
            Spacer()
            if canUndo {
                Button(action: onUndo) {
                    Text("Undo")
                        .padding(.horizontal, TK.Space.s)
                        .padding(.vertical, TK.Space.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TK.Notch.accentText)
                // Keep the visible text aligned with the panel padding despite the larger hit area.
                .padding(.trailing, -TK.Space.s)
            }
        }
        .padding(TK.Space.l)
        .frame(width: TK.Size.notchPanelWidth)
    }
}

#Preview {
    let now = Date()
    let file = TrackedFile(
        id: "preview", folderId: 1, path: "/tmp/Installer.dmg", inode: 1, volumeId: "V",
        displayName: "Installer.dmg", kind: .installer, sizeBytes: 84_000_000, state: .trashed,
        firstSeen: now, expiresAt: now, trashPath: "/tmp/.Trash/Installer.dmg", failureCount: 0, updatedAt: now)
    NoticeView(files: [file], canUndo: true, onUndo: {})
        .background(TK.Notch.surface)
}
