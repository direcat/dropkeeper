import Foundation

/// A failed prompt, list or notice action, shown in the panel for a short while (the notice's counterpart for
/// errors). A newer error replaces the older one.
struct PanelError: Equatable {
    static let window: TimeInterval = 4

    private(set) var message: String?
    private(set) var expiresAt: Date?

    var isVisible: Bool { message != nil }

    mutating func show(_ message: String, now: Date) {
        self.message = message
        expiresAt = now.addingTimeInterval(Self.window)
    }

    mutating func expireIfDue(now: Date) {
        guard let expiresAt, now >= expiresAt else { return }
        message = nil
        self.expiresAt = nil
    }
}

/// Which kind of action failed; the panel names it, so the user knows what to try again.
enum PanelFailure {
    /// A choice from the prompt, or Keep / Change time from the list.
    case update
    case undo
    case retry
    case delete

    var message: String {
        switch self {
        case .update: String(localized: "Couldn't update the file. Please try again.")
        case .undo: String(localized: "Couldn't put the file back from the Trash.")
        case .retry: String(localized: "Couldn't move the file to the Trash. Please try again later.")
        case .delete: String(localized: "Couldn't delete the file. Please try again.")
        }
    }
}
