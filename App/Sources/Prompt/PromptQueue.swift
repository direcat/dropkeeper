import DropKeeperCore

/// Pending files waiting for a decision, oldest first, minus the ones the user closed the prompt for.
struct PromptQueue: Equatable {
    private(set) var items: [TrackedFile] = []
    private var dismissed: Set<FileID> = []

    var current: TrackedFile? { items.first }

    mutating func update(pending: [TrackedFile]) {
        let pendingIds = Set(pending.map(\.id))
        dismissed.formIntersection(pendingIds)
        let visible = pending.filter { !dismissed.contains($0.id) }
        // Keep the current file first so the prompt does not jump when new files arrive.
        if let current, let kept = visible.first(where: { $0.id == current.id }) {
            items = [kept] + visible.filter { $0.id != current.id }
        } else {
            items = visible
        }
    }

    /// Closes the prompt for the current file (or the whole stack) without deciding.
    mutating func dismiss(applyToAll: Bool) {
        dismiss(ids: targets(applyToAll: applyToAll))
    }

    /// Hides these files until they leave the pending list (e.g. right after a successful decision).
    mutating func dismiss(ids: [FileID]) {
        dismissed.formUnion(ids)
        items.removeAll { ids.contains($0.id) }
    }

    func targets(applyToAll: Bool) -> [FileID] {
        applyToAll ? items.map(\.id) : current.map { [$0.id] } ?? []
    }
}
