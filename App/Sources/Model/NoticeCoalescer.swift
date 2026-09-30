import DropKeeperCore
import Foundation

/// Merges "moved to Trash" notifications that arrive within the notice window into one notice.
struct NoticeCoalescer: Equatable {
    static let window: TimeInterval = 2.5

    private(set) var files: [TrackedFile] = []
    private(set) var expiresAt: Date?

    var isVisible: Bool { !files.isEmpty }

    mutating func add(_ new: [TrackedFile], now: Date) {
        if let expiresAt, now < expiresAt {
            files += new
        } else {
            files = new
        }
        expiresAt = now.addingTimeInterval(Self.window)
    }

    mutating func expireIfDue(now: Date) {
        guard let expiresAt, now >= expiresAt else { return }
        clear()
    }

    mutating func clear() {
        files = []
        expiresAt = nil
    }
}
