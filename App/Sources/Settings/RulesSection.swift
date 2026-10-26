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

    /// A rule bound to a folder that isn't watched never sees a file.
    static func isInert(_ rule: Rule, watched: [WatchedFolder]) -> Bool {
        guard let path = rule.folderPath else { return false }
        return !watched.contains { $0.path == path }
    }
}

/// The ordered list of rules (first match wins) with add, edit, delete and drag to reorder.
struct RulesSection: View {
    @Bindable var store: SettingsDraft
    let model: AppModel
    @State private var editing: EditedRule?

    private struct EditedRule: Identifiable {
        let rule: Rule
        let isNew: Bool
        var id: UUID { rule.id }
    }

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
        .sheet(item: $editing) { edited in
            RuleEditor(rule: edited.rule, isNew: edited.isNew, folders: model.folders) { saved in
                if let index = store.draft.rules.firstIndex(where: { $0.id == saved.id }) {
                    store.draft.rules[index] = saved
                } else {
                    store.draft.rules.append(saved)
                }
            }
        }
    }

    private func row(_ rule: Binding<Rule>) -> some View {
        HStack {
            Toggle(isOn: rule.isEnabled) { Text(verbatim: rule.wrappedValue.name) }
                .labelsHidden()
            VStack(alignment: .leading) {
                Text(verbatim: rule.wrappedValue.name)
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
}
