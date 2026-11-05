import DropKeeperCore
import SwiftUI

/// Pre-expiry reminder: the due files with Delete now, Keep and Extend. Mouse-only, like the other bars: keyboard
/// focus and Return stay with the prompt (VoiceOver reaches the buttons by their labels).
struct ReminderBarView: View {
    /// The actions, left to right.
    enum Action {
        case deleteNow, keep, extend

        /// The actions, left to right.
        static let displayOrder: [Action] = [.deleteNow, .keep, .extend]

        /// The generic label; `extend` becomes "Extend by 30 min" when the files share one timer length.
        var title: String {
            switch self {
            case .deleteNow: String(localized: "Delete now")
            case .keep: String(localized: "Keep")
            case .extend: String(localized: "Extend")
            }
        }
    }

    let files: [TrackedFile]
    let onExtend: () -> Void
    let onKeep: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: TK.Space.m) {
                header
                Rectangle().fill(TK.Palette.hairline).frame(height: TK.Size.hairline)
                HStack(spacing: TK.Space.s) {
                    Spacer(minLength: 0)
                    ForEach(Action.displayOrder, id: \.self) { action in
                        button(for: action)
                    }
                }
            }
            .padding(TK.Space.l)
            .frame(width: TK.Size.panelWidth)
        }
    }

    private var header: some View {
        HStack(spacing: TK.Space.m) {
            if let file = files.first {
                LiveRing(file: file) {
                    FinderIcon(path: file.path, kind: file.kind, size: TK.Size.ringIcon)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(NoticeView.title(for: files))
                    .font(.system(size: TK.TextSize.title, weight: .semibold))
                    .foregroundStyle(TK.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Counts down while the bar is open (the soonest expiry decides); only this line ticks each second.
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Deleting in \(remaining(at: context.date))")
                        .font(.system(size: TK.TextSize.small))
                        .foregroundStyle(TK.Palette.textSecondary)
                }
            }
            Spacer(minLength: TK.Space.s)
            Button(action: onDismiss) { RoundCloseGlyph() }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(Text("Dismiss reminder"))
        }
    }

    @ViewBuilder
    private func button(for action: Action) -> some View {
        switch action {
        case .deleteNow:
            Button(action: onDelete) { label(Text(action.title)) }
                .buttonStyle(PanelTextButtonStyle(tint: TK.Palette.destructive))
                .focusable(false)
        case .keep:
            Button(action: onKeep) { label(Text(action.title)) }
                .buttonStyle(PromptButtonStyle(primary: false))
                .focusable(false)
        case .extend:
            Button(action: onExtend) { label(extendLabel) }
                .buttonStyle(PromptButtonStyle(primary: true))
                .focusable(false)
        }
    }

    private func label(_ text: Text) -> some View { text.lineLimit(1).minimumScaleFactor(0.8) }

    /// "Extend by 30 min" while every file has the same timer length (the first one's), else just "Extend".
    private var extendLabel: Text {
        let lengths = Set(files.compactMap(\.timerLength))
        guard lengths.count == 1, let length = lengths.first else { return Text(Action.extend.title) }
        return Text("Extend by \(DurationLabel.short(length))")
    }

    private func remaining(at date: Date) -> String {
        DurationLabel.remaining(max(0, (files.first?.expiresAt ?? date).timeIntervalSince(date)))
    }
}
