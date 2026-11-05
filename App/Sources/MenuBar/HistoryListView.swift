import AppKit
import DropKeeperCore
import SwiftUI

enum HistoryGroups {
    /// The files, already newest first, grouped by the day they were decided: "Today", "Yesterday", then the date
    /// (with the year when it is not the current one).
    static func make(
        _ files: [TrackedFile], now: Date, calendar: Calendar = .current
    ) -> [(title: String, files: [TrackedFile])] {
        var groups: [(title: String, files: [TrackedFile])] = []
        for file in files {
            let title = dayTitle(file.updatedAt, now: now, calendar: calendar)
            if let last = groups.indices.last, groups[last].title == title {
                groups[last].files.append(file)
            } else {
                groups.append((title, [file]))
            }
        }
        return groups
    }

    static func dayTitle(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return String(localized: "Yesterday")
        }
        let style = Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(sameYear ? style.month().day() : style.year().month().day())
    }

    /// "Moved to Trash", "Deleted permanently" or "Kept".
    static func outcomeText(_ outcome: TrackedFile.HistoryOutcome) -> String {
        switch outcome {
        case .movedToTrash: String(localized: "Moved to Trash")
        case .deletedPermanently: String(localized: "Deleted permanently")
        case .kept: String(localized: "Kept")
        }
    }
}

/// The History tab: the last decisions grouped by day, scrolling once they outgrow the card.
struct HistoryListView: View {
    let model: AppModel

    var body: some View {
        let groups = HistoryGroups.make(model.history, now: model.now)
        if groups.isEmpty {
            Text("No history yet")
                .font(.system(size: TK.TextSize.small))
                .foregroundStyle(TK.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TK.Space.xl)
        } else {
            ViewThatFits(in: .vertical) {
                content(groups)
                ScrollView { content(groups) }.scrollIndicators(.hidden)
            }
            .frame(maxHeight: TK.Size.listMaxHeight)
        }
    }

    private func content(_ groups: [(title: String, files: [TrackedFile])]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: TK.TextSize.formCaption, weight: .semibold))
                    .foregroundStyle(TK.Palette.textSecondary)
                    .padding(.horizontal, TK.Space.xs)
                    .padding(.top, TK.Space.l)
                    .padding(.bottom, TK.Space.s)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.files) { file in
                    HistoryRow(file: file, model: model)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let file: TrackedFile
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: TK.Space.m) {
            FinderIcon(path: file.path, kind: file.kind, size: TK.Size.historyIcon)
                .clipShape(RoundedRectangle(cornerRadius: TK.Radius.control))
            VStack(alignment: .leading, spacing: 1) {
                name
                Text(meta).font(.system(size: TK.TextSize.formCaption)).foregroundStyle(TK.Palette.textSecondary)
            }
            Spacer(minLength: TK.Space.s)
            if file.historyOutcome == .movedToTrash(canPutBack: true) {
                Button("Put back") { Task { await model.putBack(file.id) } }
                    .buttonStyle(PanelTextButtonStyle(tint: TK.Palette.accentText))
                    .accessibilityLabel(Text("Put back \(file.displayName)"))
            }
        }
        .padding(.horizontal, TK.Space.xs)
        .padding(.vertical, TK.Size.listRowInset)
        .background(
            hovering ? TK.Palette.fill : .clear,
            in: RoundedRectangle(cornerRadius: TK.Radius.control, style: .continuous)
        )
        .onHover { hovering = $0 }
    }

    /// A file that was kept can still be opened; a trashed or deleted one no longer lies at its path.
    @ViewBuilder
    private var name: some View {
        if file.historyOutcome == .kept, case .file(let path) = FinderReveal.target(for: file.path) {
            FileNameLink(name: file.displayName, font: nameFont) { FileOpener.open(.file(path)) }
        } else {
            Text(file.displayName).font(nameFont).foregroundStyle(TK.Palette.textPrimary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var nameFont: Font { .system(size: TK.TextSize.body, weight: .semibold) }

    /// "Moved to Trash · 10:12"; an unknown outcome shows the time alone.
    private var meta: String {
        let time = TimeLabels.timeText(file.updatedAt, calendar: .current)
        guard let outcome = file.historyOutcome else { return time }
        return "\(HistoryGroups.outcomeText(outcome)) · \(time)"
    }
}
