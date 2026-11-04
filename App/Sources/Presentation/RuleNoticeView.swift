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
        GlassCard(radius: TK.Radius.compactCard) {
            HStack(spacing: TK.Space.m) {
                FinderIcon(path: applications.first?.file.path ?? "", kind: applications.first?.file.kind ?? .other)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: TK.TextSize.title, weight: .semibold))
                        .foregroundStyle(TK.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: TK.TextSize.small))
                        .foregroundStyle(TK.Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: TK.Space.s)
                Button(action: onChange) { Text("Change") }
                    .buttonStyle(
                        PanelTextButtonStyle(
                            tint: TK.Palette.accentText, trailingInset: TK.Size.textButtonInset)
                    )
                    .focusable(false)
            }
            .padding(.horizontal, TK.Space.l)
            .padding(.vertical, TK.Space.m)
            .frame(width: TK.Size.panelWidth)
        }
        .onHover(perform: onHover)
        .accessibilityElement(children: .combine)
    }

    /// "Installers rule · delete in 1 day"; files from different rules just say they were scheduled by rules.
    private var detail: String {
        guard let first = applications.first else { return "" }
        if Set(applications.map(\.ruleId)).count > 1 { return String(localized: "Scheduled by rules") }
        let length = first.file.timerLength ?? first.file.expiresAt.map { $0.timeIntervalSinceNow } ?? 0
        return String(
            localized: "\(Self.ruleName(for: first, in: rules)) rule · delete in \(DurationLabel.short(length))")
    }

    /// The rule's current display name (default rules are translated); the name reported by the engine when the
    /// rule has since been deleted.
    static func ruleName(for application: RuleApplication, in rules: [Rule]) -> String {
        guard let rule = rules.first(where: { $0.id == application.ruleId }) else { return application.ruleName }
        return RuleSummary.displayName(for: rule)
    }
}
