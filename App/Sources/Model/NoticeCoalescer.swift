import DropKeeperCore
import Foundation

/// Merges "moved to Trash" notifications that arrive within the notice window into one notice.
/// The prompt beats the notice, so a notice that runs out while the prompt is shown is held, and gets the full
/// window once the prompt closes.
struct NoticeCoalescer: Equatable {
    static let window: TimeInterval = TK.Motion.deletedNoticeSeconds

    private(set) var files: [TrackedFile] = []
    private(set) var expiresAt: Date?
    private(set) var isHeld = false

    var isVisible: Bool { !files.isEmpty }

    mutating func add(_ new: [TrackedFile], now: Date) {
        if isHeld || expiresAt.map({ now < $0 }) == true {
            files += new
        } else {
            files = new
        }
        expiresAt = now.addingTimeInterval(Self.window)
    }

    /// The prompt closed: the notice, hidden behind it until now, shows for the full window from `now`.
    mutating func release(now: Date) {
        guard isVisible else { return }
        isHeld = false
        expiresAt = now.addingTimeInterval(Self.window)
    }

    mutating func expireIfDue(now: Date, promptShown: Bool = false) {
        guard let expiresAt, now >= expiresAt else { return }
        if promptShown {
            isHeld = true
        } else {
            clear()
        }
    }

    /// Drops these files (e.g. after a successful Undo); the rest of the notice keeps its window.
    mutating func remove(ids: [FileID]) {
        files.removeAll { ids.contains($0.id) }
        if files.isEmpty { clear() }
    }

    mutating func clear() {
        files = []
        expiresAt = nil
        isHeld = false
    }
}
