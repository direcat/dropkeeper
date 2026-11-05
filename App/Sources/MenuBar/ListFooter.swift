import DropKeeperCore
import SwiftUI

/// The list's footer: when the next deletion happens, and the "•••" menu with Settings and Quit.
struct ListFooter: View {
    let caption: String
    let actions: AppActions

    var body: some View {
        HStack {
            Text(caption)
                .font(.system(size: TK.TextSize.formCaption))
                .foregroundStyle(TK.Palette.textSecondary)
            Spacer(minLength: TK.Space.s)
            Menu {
                Button("Settings") { actions.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Quit DropKeeper") { actions.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: TK.TextSize.formCaption, weight: .bold))
                    .frame(width: TK.Size.moreButton, height: TK.Size.moreButton)
                    .background(TK.Palette.fill, in: Circle())
                    .contentShape(Circle())
                    .foregroundStyle(TK.Palette.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Settings and Quit"))
        }
    }

    /// "Last 10 · kept for 1 year", or "Last 10 · kept forever".
    static func historyCaption(retention: HistoryRetention, limit: Int = DropKeeperEngine.historyLimit) -> String {
        guard retention != .forever else {
            return String(localized: "Last \(limit) · kept forever", comment: "History footer when nothing is purged")
        }
        let kept = DurationLabel.retention(retention)
        return String(
            localized: "Last \(limit) · kept for \(kept)", comment: "History footer, e.g. Last 10 · kept for 1 year")
    }

    /// "Next deletion in 6 min" from the soonest expiry, or "No files scheduled".
    static func caption(scheduled: [TrackedFile], now: Date) -> String {
        guard let soonest = scheduled.compactMap(\.expiresAt).min() else {
            return String(localized: "No files scheduled")
        }
        let remaining = DurationLabel.remaining(max(0, soonest.timeIntervalSince(now)))
        return String(localized: "Next deletion in \(remaining)")
    }
}
