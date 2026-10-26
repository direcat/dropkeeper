import DropKeeperCore
import SwiftUI

/// The sheet that adds or edits one rule: what it matches, in which folder and how long files then stay.
struct RuleEditor: View {
    private enum MatchKind { case category, pattern }

    let isNew: Bool
    let folders: [WatchedFolder]
    let onSave: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Rule
    @State private var kind: MatchKind
    @State private var category: RuleCategory
    @State private var pattern: String

    init(rule: Rule, isNew: Bool, folders: [WatchedFolder], onSave: @escaping (Rule) -> Void) {
        self.isNew = isNew
        self.folders = folders
        self.onSave = onSave
        _rule = State(initialValue: rule)
        switch rule.match {
        case .category(let category):
            _kind = State(initialValue: .category)
            _category = State(initialValue: category)
            _pattern = State(initialValue: "")
        case .pattern(let pattern):
            _kind = State(initialValue: .pattern)
            _category = State(initialValue: .installers)
            _pattern = State(initialValue: pattern)
        }
    }

    /// Watched folders, plus the rule's own folder when it is no longer watched, so the picker still shows it.
    private var folderPaths: [String] {
        let watched = folders.map(\.path)
        guard let own = rule.folderPath, !watched.contains(own) else { return watched }
        return watched + [own]
    }

    private var normalizedPattern: String? { IgnorePattern.normalize(pattern) }

    private var canSave: Bool {
        kind == .category || (normalizedPattern != nil && !PatternCheck.matchesEverything(pattern))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $rule.name)
                Picker("What", selection: $kind) {
                    Text("Kind of file").tag(MatchKind.category)
                    Text("File name pattern").tag(MatchKind.pattern)
                }
                if kind == .category {
                    Picker("Kind", selection: $category) {
                        ForEach(RuleCategory.allCases, id: \.self) { Text(RuleSummary.categoryName($0)).tag($0) }
                    }
                } else {
                    TextField(String(localized: "Pattern, e.g. invoice*.pdf"), text: $pattern)
                    if PatternCheck.matchesEverything(pattern) {
                        Text("This pattern would match every file.")
                            .font(.system(size: TK.TextSize.formCaption))
                            .foregroundStyle(.red)
                    }
                }
                Picker("Where", selection: $rule.folderPath) {
                    Text("All watched folders").tag(String?.none)
                    ForEach(folderPaths, id: \.self) {
                        Text(verbatim: ($0 as NSString).abbreviatingWithTildeInPath).tag(Optional($0))
                    }
                }
                StepSlider(
                    "When", values: StopPresets.all, selection: $rule.duration, label: { DurationLabel.long($0) })
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(TK.Space.l)
        }
        .font(.system(size: TK.TextSize.formBody))
        .frame(width: TK.Size.ruleEditor.width, height: TK.Size.ruleEditor.height)
    }

    private func save() {
        var saved = rule
        switch kind {
        case .category: saved.match = .category(category)
        case .pattern: saved.match = .pattern(normalizedPattern ?? pattern)
        }
        if saved.name.trimmingCharacters(in: .whitespaces).isEmpty {
            saved.name =
                switch saved.match {
                case .category(let category): RuleSummary.categoryName(category)
                case .pattern(let pattern): pattern
                }
        }
        onSave(saved)
        dismiss()
    }
}
