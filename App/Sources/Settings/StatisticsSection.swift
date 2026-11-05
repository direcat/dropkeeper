import DropKeeperCore
import SwiftUI

/// The labels and values of the Statistics group, apart from the view so they can be tested.
enum StatisticsText {
    /// The shown rows; without figures (not loaded, or loading failed) every value is a dash.
    static func rows(_ statistics: Statistics?) -> [(label: String, value: String)] {
        guard let statistics else { return rows(.zero).map { ($0.label, "–") } }
        return [
            (String(localized: "Files handled"), statistics.handled.formatted()),
            (String(localized: "Moved to Trash"), statistics.movedToTrash.formatted()),
            (String(localized: "Deleted permanently"), statistics.deletedPermanently.formatted()),
            (String(localized: "Kept"), statistics.kept.formatted()),
            (String(localized: "Scheduled by rules"), statistics.scheduledByRules.formatted()),
            (String(localized: "Duplicates deleted"), statistics.duplicatesDeleted.formatted()),
            (
                String(localized: "Space freed"),
                bytes(statistics.bytesFreed)
            ),
        ]
    }
}

private func bytes(_ count: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
    return formatter.string(fromByteCount: count)
}

/// The Statistics group of the Data tab: totals over the stored history. It loads when it appears and again
/// whenever `store.historyRevision` changes (after Clear history).
struct StatisticsSection: View {
    let model: AppModel
    let store: SettingsDraft
    @State private var statistics: Statistics?

    var body: some View {
        SettingsGroup("Statistics", footer: Text("Since the oldest entry in your history.")) {
            ForEach(StatisticsText.rows(statistics), id: \.label) { row in
                SettingsRow {
                    Text(verbatim: row.label)
                } control: {
                    Text(verbatim: row.value)
                        .monospacedDigit()
                        .foregroundStyle(TK.Palette.textSecondary)
                        .frame(minWidth: TK.Size.statisticsValue, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: store.historyRevision) {
            statistics = await model.statistics()
        }
    }
}
