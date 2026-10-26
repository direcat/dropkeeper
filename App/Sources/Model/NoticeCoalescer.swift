import DropKeeperCore
import Foundation

/// Merges notifications of one kind (files moved to the Trash, rules applied) that arrive within the notice window
/// into one notice. While paused (the pointer is over the notice) the remaining time is kept and nothing expires.
struct NoticeCoalescer<Item: Equatable & Identifiable>: Equatable where Item.ID == FileID {
    let window: TimeInterval

    private(set) var items: [Item] = []
    private(set) var expiresAt: Date?
    /// The time left when the notice was paused; `nil` while it runs.
    private var remaining: TimeInterval?

    var isVisible: Bool { !items.isEmpty }
    var isPaused: Bool { remaining != nil }

    init(window: TimeInterval) {
        self.window = window
    }

    mutating func add(_ new: [Item], now: Date) {
        if isPaused || expiresAt.map({ now < $0 }) == true {
            items += new
        } else {
            items = new
        }
        expiresAt = now.addingTimeInterval(window)
        if isPaused { remaining = window }
    }

    mutating func expireIfDue(now: Date) {
        guard !isPaused, let expiresAt, now >= expiresAt else { return }
        clear()
    }

    /// Drops these items (e.g. after a successful Undo); the rest of the notice keeps its window.
    mutating func remove(ids: [FileID]) {
        items.removeAll { ids.contains($0.id) }
        if items.isEmpty { clear() }
    }

    mutating func pause(now: Date) {
        guard isVisible, !isPaused, let expiresAt else { return }
        remaining = max(0, expiresAt.timeIntervalSince(now))
    }

    mutating func resume(now: Date) {
        guard let remaining else { return }
        expiresAt = now.addingTimeInterval(remaining)
        self.remaining = nil
    }

    mutating func clear() {
        items = []
        expiresAt = nil
        remaining = nil
    }
}
