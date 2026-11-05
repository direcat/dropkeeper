import DropKeeperCore
import Foundation

/// Which scheduled files are inside their pre-expiry reminder window and not yet dismissed.
struct ReminderTracker: Equatable {
    /// Soonest expiry first.
    private(set) var due: [TrackedFile] = []
    /// Keyed by expiry as well, so extending a file re-arms its reminder.
    private var dismissed: Set<Key> = []
    /// Every (file, expiry) a reminder was due for, so a deletion can tell whether its reminder was due (the
    /// model's view: the panel may have been covered).
    /// A dismissed or auto-hidden reminder still counts. An extended file has a new expiry and so a new key.
    private var shown: Set<Key> = []

    private struct Key: Hashable {
        let id: FileID
        let expiresAt: Date
    }

    mutating func update(scheduled: [TrackedFile], now: Date, enabled: Bool, leadTime: TimeInterval) {
        let current = Set(scheduled.compactMap { file in file.expiresAt.map { Key(id: file.id, expiresAt: $0) } })
        dismissed.formIntersection(current)
        due = Self.inWindow(scheduled, now: now, enabled: enabled, leadTime: leadTime)
            .filter { !dismissed.contains(Key(id: $0.id, expiresAt: $0.expiresAt!)) }
        shown.formUnion(due.map { Key(id: $0.id, expiresAt: $0.expiresAt!) })
        // The deletion notification arrives within moments of the expiry; older records are dead weight.
        shown = shown.filter { $0.expiresAt > now.addingTimeInterval(-Self.shownMemory) }
    }

    private static let shownMemory: TimeInterval = 600

    /// True when a reminder was due for this file's current expiry (it may be dismissed or hidden by now).
    func wasShown(_ file: TrackedFile) -> Bool {
        guard let expiresAt = file.expiresAt else { return false }
        return shown.contains(Key(id: file.id, expiresAt: expiresAt))
    }

    mutating func dismiss(ids: [FileID]) {
        let ids = Set(ids)
        for file in due where ids.contains(file.id) {
            if let expiresAt = file.expiresAt { dismissed.insert(Key(id: file.id, expiresAt: expiresAt)) }
        }
        due.removeAll { ids.contains($0.id) }
    }

    /// The next moment a reminder window opens; nil when none is ahead. The expiry itself is covered by `Countdown`.
    func nextWake(scheduled: [TrackedFile], now: Date, enabled: Bool, leadTime: TimeInterval) -> Date? {
        guard enabled else { return nil }
        return scheduled.compactMap { file -> Date? in
            guard let expiresAt = file.expiresAt, Self.qualifies(file, leadTime: leadTime) else { return nil }
            let start = expiresAt.addingTimeInterval(-leadTime)
            return start > now && !dismissed.contains(Key(id: file.id, expiresAt: expiresAt)) ? start : nil
        }.min()
    }

    private static func qualifies(_ file: TrackedFile, leadTime: TimeInterval) -> Bool {
        guard let length = file.timerLength else { return false }
        return length > leadTime
    }

    private static func inWindow(
        _ files: [TrackedFile], now: Date, enabled: Bool, leadTime: TimeInterval
    ) -> [TrackedFile] {
        guard enabled else { return [] }
        return files.filter { file in
            guard let expiresAt = file.expiresAt, qualifies(file, leadTime: leadTime) else { return false }
            return expiresAt.addingTimeInterval(-leadTime) <= now && now < expiresAt
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }
}
