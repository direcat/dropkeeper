import DropKeeperCore
import SwiftUI

enum PatternCheck {
    /// True when the pattern, once normalized, is only `*` and `?`: it would match every file name.
    static func matchesEverything(_ raw: String) -> Bool {
        guard let pattern = IgnorePattern.normalize(raw) else { return false }
        return pattern.allSatisfy { $0 == "*" || $0 == "?" }
    }
}

/// Duplicate detection and the list of file-name patterns DropKeeper never tracks.
struct IgnoredFilesSection: View {
    @Bindable var store: SettingsDraft
    @State private var newPattern = ""

    private var refused: Bool { PatternCheck.matchesEverything(newPattern) }

    var body: some View {
        SettingsGroup {
            SettingsToggleRow("Detect duplicate downloads", isOn: $store.draft.duplicateDetection)
        }
        SettingsGroup("Ignored files", footer: footer) {
            ForEach(store.draft.ignoredPatterns, id: \.self) { pattern in
                SettingsRow {
                    Text(verbatim: pattern)
                } control: {
                    Button {
                        store.draft.ignoredPatterns.removeAll { $0 == pattern }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Remove pattern"))
                    .accessibilityLabel(Text("Remove pattern"))
                }
            }
            HStack {
                // The String overload keeps the `*` in the placeholder from being read as Markdown.
                TextField(String(localized: "Pattern, e.g. *.dmg or ~$*"), text: $newPattern)
                    .textFieldStyle(.plain)
                    .onSubmit(addPattern)
                Button("Add", action: addPattern)
                    .disabled(IgnorePattern.normalize(newPattern) == nil || refused)
            }
            .padding(.vertical, TK.Size.settingsRowInset)
            .frame(minHeight: TK.Size.settingsRow)
            if refused {
                SettingsRow {
                    Text("This pattern would match every file.")
                        .settingsCaption()
                        .foregroundStyle(TK.Palette.destructive)
                } control: {
                    EmptyView()
                }
            }
        }
    }

    /// The String overload keeps the `*` from being read as Markdown.
    private var footer: Text {
        Text(String(localized: "* matches any characters and ? matches one. A plain word such as zip means *.zip."))
    }

    private func addPattern() {
        guard !refused, let pattern = IgnorePattern.normalize(newPattern),
            !store.draft.ignoredPatterns.contains(pattern)
        else { return }
        store.draft.ignoredPatterns.append(pattern)
        newPattern = ""
    }
}
