import DropKeeperCore
import SwiftUI

/// Pre-expiry reminder: the due files with Extend, Keep and Delete now. Mouse-only, like the other bars: keyboard
/// focus and Return stay with the prompt (VoiceOver reaches the buttons by their labels).
struct ReminderBarView: View {
    let files: [TrackedFile]
    let onExtend: () -> Void
    let onKeep: () -> Void
    let onDelete: () -> Void
    /// Permanent deletion asks for confirmation first, which the label announces with an ellipsis.
    var deleteAsksConfirmation = false
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TK.Space.m) {
            HStack(spacing: TK.Space.m) {
                FinderIcon(path: files.first?.path ?? "", kind: files.first?.kind ?? .other)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NoticeView.title(for: files))
                        .font(.system(size: TK.TextSize.title, weight: .semibold))
                        .foregroundStyle(TK.Notch.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Counts down while the bar is open (the soonest expiry decides).
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Deleted in \(remaining(at: context.date))")
                            .font(.system(size: TK.TextSize.small))
                            .foregroundStyle(TK.Notch.urgent)
                    }
                }
                Spacer(minLength: TK.Space.s)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: TK.TextSize.small, weight: .regular))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(TK.Notch.textSecondary)
                .accessibilityLabel(Text("Dismiss reminder"))
            }
            HStack(spacing: TK.Space.s) {
                button(extendLabel, primary: true, action: onExtend)
                button(Text("Keep"), primary: false, action: onKeep)
                button(deleteLabel, primary: false, action: onDelete)
                Spacer(minLength: 0)
            }
        }
        .padding(TK.Space.l)
        .frame(width: TK.Size.notchPanelWidth)
    }

    private func button(_ label: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { label.lineLimit(1).minimumScaleFactor(0.8) }
            .buttonStyle(PromptButtonStyle(primary: primary))
            .focusable(false)
    }

    private var deleteLabel: Text { deleteAsksConfirmation ? Text("Delete now…") : Text("Delete now") }

    /// "Extend by 30 min" while every file has the same timer length (the first one's), else just "Extend".
    private var extendLabel: Text {
        let lengths = Set(files.compactMap(\.timerLength))
        guard lengths.count == 1, let length = lengths.first else { return Text("Extend") }
        return Text("Extend by \(DurationLabel.short(length))")
    }

    private func remaining(at date: Date) -> String {
        DurationLabel.remaining(max(0, (files.first?.expiresAt ?? date).timeIntervalSince(date)))
    }
}
