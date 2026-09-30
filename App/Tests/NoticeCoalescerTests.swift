import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@Test func reviewFocusTrashesWithinWindowAreMerged() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(2))
    #expect(notice.files.map(\.id) == ["a", "b"])
    #expect(notice.expiresAt == base.addingTimeInterval(4.5))
    notice.expireIfDue(now: base.addingTimeInterval(4))
    #expect(notice.isVisible)
    notice.expireIfDue(now: base.addingTimeInterval(4.5))
    #expect(!notice.isVisible)
}

@Test func trashAfterWindowStartsANewNotice() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(3))
    #expect(notice.files.map(\.id) == ["b"])
}

@Test func clearHidesImmediately() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.clear()
    #expect(!notice.isVisible)
    #expect(notice.expiresAt == nil)
}

@Test func noticeWaitsWhileThePromptIsShownThenGetsTheFullWindow() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.expireIfDue(now: base.addingTimeInterval(3), promptShown: true)
    #expect(notice.isVisible)
    // A second trash during a long prompt joins the held notice, so Undo covers both.
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(10))
    #expect(notice.files.map(\.id) == ["a", "b"])
    notice.release(now: base.addingTimeInterval(20))
    #expect(notice.expiresAt == base.addingTimeInterval(22.5))
    notice.expireIfDue(now: base.addingTimeInterval(22))
    #expect(notice.isVisible)
    notice.expireIfDue(now: base.addingTimeInterval(22.5))
    #expect(!notice.isVisible)
}

@Test func releaseRestartsTheWindowEvenBeforeItRanOut() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.release(now: base.addingTimeInterval(1))
    #expect(notice.expiresAt == base.addingTimeInterval(3.5))
    var empty = NoticeCoalescer()
    empty.release(now: base)
    #expect(empty.expiresAt == nil)
}

@Test func panelErrorShowsForItsWindowAndTheLatestWins() {
    var error = PanelError()
    #expect(!error.isVisible)
    error.show("First", now: base)
    error.show("Second", now: base.addingTimeInterval(1))
    #expect(error.message == "Second")
    #expect(error.expiresAt == base.addingTimeInterval(1 + PanelError.window))
    error.expireIfDue(now: base.addingTimeInterval(PanelError.window))
    #expect(error.isVisible)
    error.expireIfDue(now: base.addingTimeInterval(1 + PanelError.window))
    #expect(!error.isVisible)
    #expect(error.expiresAt == nil)
}

@Test func removeKeepsFilesMergedInMeanwhile() {
    var notice = NoticeCoalescer()
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(1))
    notice.remove(ids: ["a"])
    #expect(notice.files.map(\.id) == ["b"])
    #expect(notice.expiresAt == base.addingTimeInterval(3.5))
    notice.remove(ids: ["b"])
    #expect(!notice.isVisible)
    #expect(notice.expiresAt == nil)
}
