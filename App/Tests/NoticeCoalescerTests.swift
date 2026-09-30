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
