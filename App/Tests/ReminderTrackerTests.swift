import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

/// A scheduled file whose timer was `length` seconds long and ends `expiresIn` seconds after `base`.
private func timed(_ id: String, length: TimeInterval, expiresIn: TimeInterval) -> TrackedFile {
    var file = scheduledFile(expiresIn: expiresIn, id: id)
    file.updatedAt = base.addingTimeInterval(expiresIn - length)
    file.scheduleDuration = length
    return file
}

private func tracker(_ files: [TrackedFile], now: TimeInterval = 0, enabled: Bool = true, lead: TimeInterval = 300)
    -> ReminderTracker
{
    var tracker = ReminderTracker()
    tracker.update(scheduled: files, now: base.addingTimeInterval(now), enabled: enabled, leadTime: lead)
    return tracker
}

@Test func dueInsideLeadWindowOnly() {
    let file = timed("a", length: 3600, expiresIn: 1000)
    #expect(tracker([file], now: 0).due.isEmpty)  // 1000 s left, window opens at 700
    #expect(tracker([file], now: 700).due.map(\.id) == ["a"])
    #expect(tracker([file], now: 999).due.map(\.id) == ["a"])
    #expect(tracker([file], now: 1000).due.isEmpty)  // expired
}

@Test func shortTimerNeverReminds() {
    let file = timed("a", length: 300, expiresIn: 100)
    #expect(tracker([file], now: 0, lead: 300).due.isEmpty)
    #expect(tracker([timed("b", length: 301, expiresIn: 100)], now: 0, lead: 300).due.map(\.id) == ["b"])
}

@Test func dismissedStaysDismissedUntilExtended() {
    let file = timed("a", length: 3600, expiresIn: 200)
    var tracker = tracker([file], now: 0)
    tracker.dismiss(ids: ["a"])
    #expect(tracker.due.isEmpty)
    tracker.update(scheduled: [file], now: base.addingTimeInterval(10), enabled: true, leadTime: 300)
    #expect(tracker.due.isEmpty)

    // Extending moves the expiry, which re-arms the reminder once the new window opens.
    let extended = timed("a", length: 3600, expiresIn: 1200)
    tracker.update(scheduled: [extended], now: base.addingTimeInterval(10), enabled: true, leadTime: 300)
    #expect(tracker.due.isEmpty)
    tracker.update(scheduled: [extended], now: base.addingTimeInterval(950), enabled: true, leadTime: 300)
    #expect(tracker.due.map(\.id) == ["a"])
}

@Test func disabledNeverDue() {
    let file = timed("a", length: 3600, expiresIn: 100)
    #expect(tracker([file], now: 0, enabled: false).due.isEmpty)
    #expect(
        ReminderTracker().nextWake(
            scheduled: [timed("b", length: 3600, expiresIn: 1000)], now: base, enabled: false, leadTime: 300) == nil)
}

@Test func nextWakeIsEarliestReminderStart() {
    let files = [
        timed("late", length: 3600, expiresIn: 2000),  // window opens at 1700
        timed("soon", length: 3600, expiresIn: 1000),  // window opens at 700
        timed("open", length: 3600, expiresIn: 100),  // already inside, nothing to wait for
        timed("short", length: 300, expiresIn: 500),  // never reminds
    ]
    let wake = ReminderTracker().nextWake(scheduled: files, now: base, enabled: true, leadTime: 300)
    #expect(wake == base.addingTimeInterval(700))
    #expect(ReminderTracker().nextWake(scheduled: [], now: base, enabled: true, leadTime: 300) == nil)
}

@Test func fileLeavingScheduledDropsOut() {
    let later = timed("a", length: 3600, expiresIn: 200)
    let sooner = timed("b", length: 3600, expiresIn: 100)
    var tracker = tracker([later, sooner])
    #expect(tracker.due.map(\.id) == ["b", "a"])  // soonest first
    tracker.update(scheduled: [later], now: base, enabled: true, leadTime: 300)
    #expect(tracker.due.map(\.id) == ["a"])
}
