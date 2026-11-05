import DropKeeperCore
import Foundation
import SwiftUI
import Testing

@testable import DropKeeper

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

private func historyFile(_ id: String, state: FileState = .kept, trashPath: String? = nil, at date: Date) -> TrackedFile
{
    var file = scheduledFile(expiresIn: 0, id: id)
    file.state = state
    file.expiresAt = nil
    file.trashPath = trashPath
    file.updatedAt = date
    return file
}

@Suite struct HistoryGroupsTests {
    // 2026-11-04 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_793_600)

    @Test func groupsTodayYesterdayAndDates() {
        let day: TimeInterval = 86_400
        let files = [
            historyFile("a", at: now - 60), historyFile("b", at: now - 3600), historyFile("c", at: now - day),
            historyFile("d", at: now - 5 * day),
        ]
        let groups = HistoryGroups.make(files, now: now, calendar: utcCalendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Oct 30"])
        #expect(groups.map { $0.files.map(\.id) } == [["a", "b"], ["c"], ["d"]])
    }

    @Test func otherYearsShowTheYear() {
        let old = historyFile("x", at: now - 400 * 86_400)
        let groups = HistoryGroups.make([old], now: now, calendar: utcCalendar)
        #expect(groups.first?.title.contains("2025") == true)
    }

    @Test func outcomes() {
        #expect(historyFile("k", at: now).historyOutcome == .kept)
        #expect(HistoryGroups.outcomeText(.kept) == "Kept")
        #expect(HistoryGroups.outcomeText(.deletedPermanently) == "Deleted permanently")
        #expect(HistoryGroups.outcomeText(.movedToTrash(canPutBack: true)) == "Moved to Trash")
    }

    @Test func footerCaption() {
        #expect(ListFooter.historyCaption(retention: .oneYear, limit: 10) == "Last 10 · kept for 1 year")
        #expect(ListFooter.historyCaption(retention: .forever, limit: 10) == "Last 10 · kept forever")
    }
}

@MainActor
@Suite(.serialized) struct HistoryViewTests {
    private func height(of model: AppModel) throws -> Int {
        let renderer = ImageRenderer(content: HistoryListView(model: model).frame(width: TK.Size.panelWidth))
        return try #require(renderer.cgImage).height
    }

    @Test func rowsRenderTallerThanTheEmptyState() throws {
        let suite = "HistoryViewTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: UserDefaults(suiteName: suite)!, applyLoginItem: { _ in })
        let empty = try height(of: model)
        let files = [
            historyFile("t", state: .trashed, trashPath: "/tmp/t", at: Date()),
            historyFile("p", state: .trashed, at: Date()), historyFile("k", at: Date()),
        ]
        #expect(files.map(\.historyOutcome) == [.movedToTrash(canPutBack: true), .deletedPermanently, .kept])
        model.applyHistory(files)
        #expect(model.history.count == 3)
        #expect(try height(of: model) > empty)
    }
}
