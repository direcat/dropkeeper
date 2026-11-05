import DropKeeperCore
import SwiftUI

/// The labels and values of the Statistics group, apart from the view so they can be tested.
enum StatisticsText {
    static func rows(_ statistics: Statistics) -> [(label: String, value: String)] {
        [
            (String(localized: "Files handled"), statistics.handled.formatted()),
            (String(localized: "Moved to Trash"), statistics.movedToTrash.formatted()),
            (String(localized: "Deleted permanently"), statistics.deletedPermanently.formatted()),
            (String(localized: "Kept"), statistics.kept.formatted()),
            (String(localized: "Scheduled by rules"), statistics.scheduledByRules.formatted()),
            (String(localized: "Duplicates deleted"), statistics.duplicatesDeleted.formatted()),
            (
                String(localized: "Space freed"),
                ByteCountFormatter.string(fromByteCount: statistics.bytesFreed, countStyle: .file)
            ),
        ]
    }
}

/// The Statistics group of the Data tab: totals over the stored history. It loads when it appears and again
/// whenever `store.historyRevision` changes (after Clear history).
struct StatisticsSection: View {
    let model: AppModel
    let store: SettingsDraft
    @State private var statistics = Statistics.zero

    var body: some View {
        SettingsGroup("Statistics", footer: Text("Since the oldest entry in your history.")) {
            ForEach(StatisticsText.rows(statistics), id: \.label) { row in
                SettingsRow(caption: nil) {
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
            if let fresh = await model.statistics() { statistics = fresh }
        }
    }
}
