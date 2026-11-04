import DropKeeperCore
import Foundation

/// The countdown behind a notification that hides by itself. Pure state: the owner passes `now` and schedules the
/// wake-up. A duration of `Settings.notificationTimeoutNever` makes every call a no-op.
struct AutoHideTimer: Equatable {
    let duration: TimeInterval
    /// When the running countdown ends; nil while stopped or paused.
    private(set) var expiresAt: Date?
    /// What was left when the countdown was paused; nil unless paused.
    private var pausedRemaining: TimeInterval?

    init(duration: TimeInterval) { self.duration = duration }

    private var isEnabled: Bool { duration > 0 }
    var isPaused: Bool { pausedRemaining != nil }

    mutating func start(now: Date) {
        guard isEnabled else { return }
        pausedRemaining = nil
        expiresAt = now.addingTimeInterval(duration)
    }

    /// Full time again; a paused countdown stays paused, with the full time left.
    mutating func restart(now: Date) {
        guard isEnabled else { return }
        if isPaused { pausedRemaining = duration } else { start(now: now) }
    }

    mutating func pause(now: Date) {
        guard isEnabled, let expiresAt else { return }
        pausedRemaining = max(0, expiresAt.timeIntervalSince(now))
        self.expiresAt = nil
    }

    mutating func resume(now: Date) {
        guard isEnabled, let pausedRemaining else { return }
        self.pausedRemaining = nil
        expiresAt = now.addingTimeInterval(pausedRemaining)
    }

    mutating func stop() {
        expiresAt = nil
        pausedRemaining = nil
    }

    /// Time left, nil when stopped (or Never).
    func remaining(now: Date) -> TimeInterval? {
        if let pausedRemaining { return pausedRemaining }
        return expiresAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    func isDue(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}
