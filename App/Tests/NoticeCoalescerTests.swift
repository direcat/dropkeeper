import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@Test func reviewFocusTrashesWithinWindowAreMerged() {
    var notice = NoticeCoalescer<TrackedFile>(window: 2.5)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(2))
    #expect(notice.items.map(\.id) == ["a", "b"])
    #expect(notice.expiresAt == base.addingTimeInterval(4.5))
    notice.expireIfDue(now: base.addingTimeInterval(4))
    #expect(notice.isVisible)
    notice.expireIfDue(now: base.addingTimeInterval(4.5))
    #expect(!notice.isVisible)
}

@Test func trashAfterWindowStartsANewNotice() {
    var notice = NoticeCoalescer<TrackedFile>(window: 2.5)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(3))
    #expect(notice.items.map(\.id) == ["b"])
}

@Test func clearHidesImmediately() {
    var notice = NoticeCoalescer<TrackedFile>(window: 2.5)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.clear()
    #expect(!notice.isVisible)
    #expect(notice.expiresAt == nil)
}

@Test func pausedNoticeDoesNotExpire() {
    var notice = NoticeCoalescer<TrackedFile>(window: 6)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.pause(now: base.addingTimeInterval(4))
    notice.expireIfDue(now: base.addingTimeInterval(60))
    #expect(notice.isVisible)
}

@Test func resumeKeepsRemainingTime() {
    var notice = NoticeCoalescer<TrackedFile>(window: 6)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.pause(now: base.addingTimeInterval(4))
    notice.resume(now: base.addingTimeInterval(20))
    #expect(notice.expiresAt == base.addingTimeInterval(22))
    notice.expireIfDue(now: base.addingTimeInterval(21))
    #expect(notice.isVisible)
    notice.expireIfDue(now: base.addingTimeInterval(22))
    #expect(!notice.isVisible)
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
    var notice = NoticeCoalescer<TrackedFile>(window: 2.5)
    notice.add([scheduledFile(expiresIn: 0, id: "a")], now: base)
    notice.add([scheduledFile(expiresIn: 0, id: "b")], now: base.addingTimeInterval(1))
    notice.remove(ids: ["a"])
    #expect(notice.items.map(\.id) == ["b"])
    #expect(notice.expiresAt == base.addingTimeInterval(3.5))
    notice.remove(ids: ["b"])
    #expect(!notice.isVisible)
    #expect(notice.expiresAt == nil)
}
