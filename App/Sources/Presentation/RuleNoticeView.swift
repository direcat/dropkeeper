import DropKeeperCore
import SwiftUI

/// "A rule scheduled this file" notice with Change. Hovering it pauses its countdown so there is time to click.
struct RuleNoticeView: View {
    let applications: [RuleApplication]
    let onChange: () -> Void
    let onHover: (Bool) -> Void

    private var title: String { NoticeView.title(for: applications.map(\.file)) }

    var body: some View {
        HStack(spacing: TK.Space.m) {
            FinderIcon(path: applications.first?.file.path ?? "", kind: applications.first?.file.kind ?? .other)
            Text(line)
                .font(.system(size: TK.TextSize.small))
                .foregroundStyle(TK.Notch.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: TK.Space.s)
            Button(action: onChange) {
                Text("Change")
                    .padding(.horizontal, TK.Space.s)
                    .padding(.vertical, TK.Space.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: TK.TextSize.title, weight: .medium))
            .foregroundStyle(TK.Notch.accentText)
            // Keep the visible text aligned with the panel padding despite the larger hit area.
            .padding(.trailing, -TK.Space.s)
        }
        .padding(TK.Space.l)
        .frame(width: TK.Size.notchPanelWidth)
        .onHover(perform: onHover)
        .accessibilityElement(children: .combine)
    }

    /// "report.dmg — deleted in 1 day (Installers)"; for several files the first rule's name.
    private var line: String {
        guard let first = applications.first else { return "" }
        let length = first.file.timerLength ?? first.file.expiresAt.map { $0.timeIntervalSinceNow } ?? 0
        return String(localized: "\(title) — deleted in \(DurationLabel.short(length)) (\(first.ruleName))")
    }
}
