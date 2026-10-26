import DropKeeperCore
import SwiftUI

/// Display text and sanity checks for a rule, kept apart from the views so they can be tested.
enum RuleSummary {
    static func categoryName(_ category: RuleCategory) -> String {
        switch category {
        case .installers: String(localized: "Installers")
        case .images: String(localized: "Images")
        case .archives: String(localized: "Archives")
        case .invitationsAndContacts: String(localized: "Invitations & contacts")
        case .screenshots: String(localized: "Screenshots")
        }
    }

    /// "Installers · all folders · 1 day": what it matches, where, and when it deletes.
    static func text(for rule: Rule) -> String {
        let what =
            switch rule.match {
            case .category(let category): categoryName(category)
            case .pattern(let pattern): pattern
            }
        let folder = rule.folderPath.map { ($0 as NSString).lastPathComponent } ?? String(localized: "all folders")
        return [what, folder, DurationLabel.long(rule.duration)].joined(separator: " · ")
    }

    /// Core's default rules carry English names; a default rule still bearing its original name shows it translated.
    static func displayName(for rule: Rule) -> String {
        guard let original = Rule.defaults(home: "").first(where: { $0.id == rule.id }), original.name == rule.name
        else { return rule.name }
        switch original.match {
        case .category(.screenshots): return String(localized: "Screenshots on Desktop")
        case .category(let category): return categoryName(category)
        case .pattern: return rule.name
        }
    }

    /// A rule bound to a folder that isn't watched never sees a file.
    static func isInert(_ rule: Rule, watched: [WatchedFolder]) -> Bool {
        guard let path = rule.folderPath else { return false }
        return !watched.contains { $0.path == path }
    }
}

/// First match wins, so a rule's position matters.
enum RuleOrder {
    /// `rules` with the rule `id` moved by `offset` places, clamped to the ends; unchanged when `id` is unknown.
    static func move(_ rules: [Rule], id: UUID, by offset: Int) -> [Rule] {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return rules }
        let target = min(max(index + offset, 0), rules.count - 1)
        var result = rules
        result.insert(result.remove(at: index), at: target)
        return result
    }
}

/// A rule open in the editor sheet.
struct EditedRule: Identifiable {
    let rule: Rule
    let isNew: Bool
    var id: UUID { rule.id }
}

/// The ordered list of rules (first match wins) with add, edit, delete and drag to reorder.
struct RulesSection: View {
    @Bindable var store: SettingsDraft
    let model: AppModel
    @Binding var editing: EditedRule?

    var body: some View {
        Section("Rules") {
            ForEach($store.draft.rules) { $rule in
                row($rule)
            }
            .onMove { store.draft.rules.move(fromOffsets: $0, toOffset: $1) }
            Button("Add rule") {
                editing = EditedRule(
                    rule: Rule(name: "", match: .category(.installers), duration: 86_400), isNew: true)
            }
        }
    }

    private func row(_ rule: Binding<Rule>) -> some View {
        HStack {
            Toggle(isOn: rule.isEnabled) { Text(verbatim: RuleSummary.displayName(for: rule.wrappedValue)) }
                .labelsHidden()
            VStack(alignment: .leading) {
                Text(verbatim: RuleSummary.displayName(for: rule.wrappedValue))
                Text(verbatim: RuleSummary.text(for: rule.wrappedValue))
                    .font(.system(size: TK.TextSize.formCaption))
                    .foregroundStyle(.secondary)
                if RuleSummary.isInert(rule.wrappedValue, watched: model.folders),
                    let path = rule.wrappedValue.folderPath
                {
                    let folder = (path as NSString).abbreviatingWithTildeInPath
                    Text("\(folder) isn't a watched folder, so this rule does nothing.")
                        .font(.system(size: TK.TextSize.formCaption))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            moveButton("chevron.up", label: "Move up", rule: rule.wrappedValue, offset: -1)
            moveButton("chevron.down", label: "Move down", rule: rule.wrappedValue, offset: 1)
            Button {
                editing = EditedRule(rule: rule.wrappedValue, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(Text("Edit rule"))
            .accessibilityLabel(Text("Edit rule"))
            Button {
                store.draft.rules.removeAll { $0.id == rule.wrappedValue.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(Text("Delete rule"))
            .accessibilityLabel(Text("Delete rule"))
        }
    }

    private func moveButton(_ symbol: String, label: LocalizedStringKey, rule: Rule, offset: Int) -> some View {
        let rules = store.draft.rules
        let index = rules.firstIndex { $0.id == rule.id } ?? 0
        let atEnd = offset < 0 ? index == 0 : index == rules.count - 1
        return Button {
            store.draft.rules = RuleOrder.move(rules, id: rule.id, by: offset)
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .disabled(atEnd)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}
