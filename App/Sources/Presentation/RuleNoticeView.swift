import DropKeeperCore
import SwiftUI

/// "A rule scheduled this file" notice with Change. Hovering it pauses its countdown so there is time to click.
struct RuleNoticeView: View {
    let applications: [RuleApplication]
    let rules: [Rule]
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

    /// "report.dmg — deleted in 1 day (Installers)"; several files from one rule use that rule, files from
    /// different rules just say they were scheduled by rules.
    private var line: String {
        guard let first = applications.first else { return "" }
        if Set(applications.map(\.ruleId)).count > 1 {
            return String(localized: "\(applications.count) files — scheduled by rules")
        }
        let length = first.file.timerLength ?? first.file.expiresAt.map { $0.timeIntervalSinceNow } ?? 0
        return String(
            localized: "\(title) — deleted in \(DurationLabel.short(length)) (\(Self.ruleName(for: first, in: rules)))")
    }

    /// The rule's current display name (default rules are translated); the name reported by the engine when the
    /// rule has since been deleted.
    static func ruleName(for application: RuleApplication, in rules: [Rule]) -> String {
        guard let rule = rules.first(where: { $0.id == application.ruleId }) else { return application.ruleName }
        return RuleSummary.displayName(for: rule)
    }
}
