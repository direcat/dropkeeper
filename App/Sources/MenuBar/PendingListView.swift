import DropKeeperCore
import SwiftUI

enum ListTab: String, CaseIterable {
    case upcoming, history

    var title: String {
        switch self {
        case .upcoming: String(localized: "Upcoming", comment: "Menu bar list tab: files waiting or scheduled")
        case .history: String(localized: "History", comment: "Menu bar list tab: files DropKeeper has dealt with")
        }
    }
}

/// The menu bar list: one glass card with an Upcoming / History switch, the tab's content and a footer.
struct PendingListView: View {
    let model: AppModel
    let actions: AppActions
    @State private var tab = ListTab.upcoming

    var body: some View {
        GlassCard {
            VStack(spacing: 0) {
                if let message = model.panelError.message {
                    PanelErrorBanner(message: message)
                        .padding(.bottom, TK.Space.s)
                }
                ListSegmentedControl(selection: $tab)
                switch tab {
                case .upcoming:
                    UpcomingListView(model: model, actions: actions)
                case .history:
                    HistoryListView(model: model)
                }
                ListFooter(
                    caption: tab == .history
                        ? ListFooter.historyCaption(retention: model.settings.historyRetention)
                        : ListFooter.caption(scheduled: model.scheduled, now: model.now),
                    actions: actions
                )
                .padding(.top, TK.Space.m)
            }
            .padding(TK.Space.l)
            .frame(width: TK.Size.panelWidth)
        }
    }
}

/// A two-segment switch in the card's own style: a soft track with a raised selected segment.
private struct ListSegmentedControl: View {
    @Binding var selection: ListTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ListTab.allCases, id: \.self) { tab in
                segment(tab)
            }
        }
        .padding(TK.Size.segmentPadding)
        .background(TK.Palette.fillStrong, in: RoundedRectangle(cornerRadius: TK.Radius.segment, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("List sections"))
    }

    private func segment(_ tab: ListTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(reduceMotion ? nil : TK.Motion.select) { selection = tab }
        } label: {
            Text(tab.title)
                .font(.system(size: TK.TextSize.small, weight: .medium))
                .foregroundStyle(selected ? TK.Palette.textPrimary : TK.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TK.Size.listRowInset)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: TK.Radius.segmentInner, style: .continuous)
                            .fill(TK.Palette.segmentOn)
                            .shadow(
                                color: .black.opacity(TK.Shadow.knobOpacity / 2), radius: TK.Shadow.knobRadius,
                                y: TK.Shadow.knobOffset)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
