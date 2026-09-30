import DropKeeperCore
import Foundation

enum Countdown {
    static let threshold: TimeInterval = 10

    /// Whole seconds left for the soonest expiry, if it is within the threshold.
    static func urgentSeconds(scheduled: [TrackedFile], now: Date) -> Int? {
        guard let soonest = soonestExpiry(scheduled, now: now) else { return nil }
        let left = soonest.timeIntervalSince(now)
        guard left <= threshold else { return nil }
        return max(0, Int(left.rounded(.up)))
    }

    /// When the UI must next refresh time-dependent labels; nil when nothing is scheduled.
    static func nextRefresh(scheduled: [TrackedFile], now: Date) -> Date? {
        guard let soonest = soonestExpiry(scheduled, now: now) else { return nil }
        let left = soonest.timeIntervalSince(now)
        if left <= threshold { return now.addingTimeInterval(1) }
        return min(soonest.addingTimeInterval(-threshold), now.addingTimeInterval(60))
    }

    private static func soonestExpiry(_ files: [TrackedFile], now: Date) -> Date? {
        files.compactMap(\.expiresAt).filter { $0 > now.addingTimeInterval(-1) }.min()
    }
}
