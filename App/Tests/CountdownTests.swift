import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

func scheduledFile(expiresIn seconds: TimeInterval, id: String = UUID().uuidString) -> TrackedFile {
    TrackedFile(
        id: id, folderId: 1, path: "/tmp/\(id)", inode: 1, volumeId: "V", displayName: id, kind: .other,
        sizeBytes: 1, state: .scheduled, firstSeen: base, expiresAt: base.addingTimeInterval(seconds),
        trashPath: nil, failureCount: 0, updatedAt: base)
}

@Test func urgentOnlyWithinTenSeconds() {
    #expect(Countdown.urgentSeconds(scheduled: [scheduledFile(expiresIn: 11)], now: base) == nil)
    #expect(Countdown.urgentSeconds(scheduled: [scheduledFile(expiresIn: 9.2)], now: base) == 10)
    #expect(
        Countdown.urgentSeconds(scheduled: [scheduledFile(expiresIn: 600), scheduledFile(expiresIn: 3)], now: base)
            == 3)
    #expect(Countdown.urgentSeconds(scheduled: [], now: base) == nil)
}

@Test func nextRefreshTimes() {
    // Far away: wake when the countdown starts, but at least once a minute for "in N min" labels.
    #expect(Countdown.nextRefresh(scheduled: [scheduledFile(expiresIn: 30)], now: base) == base.addingTimeInterval(20))
    #expect(
        Countdown.nextRefresh(scheduled: [scheduledFile(expiresIn: 3600)], now: base) == base.addingTimeInterval(60))
    // Inside the countdown: every second.
    #expect(Countdown.nextRefresh(scheduled: [scheduledFile(expiresIn: 5)], now: base) == base.addingTimeInterval(1))
    #expect(Countdown.nextRefresh(scheduled: [], now: base) == nil)
}
