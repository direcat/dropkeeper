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

    /// Brings these files back (e.g. a file closed with Esc, picked from the list) and shows them first.
    /// Ids that are no longer pending are ignored.
    mutating func restore(ids: [FileID], pending: [TrackedFile]) {
        dismissed.subtract(ids)
        let visible = pending.filter { !dismissed.contains($0.id) }
        let restored = visible.filter { ids.contains($0.id) }
        guard !restored.isEmpty else {
            update(pending: pending)
            return
        }
        items = restored + visible.filter { !ids.contains($0.id) }
    }

    /// The files an action from the prompt applies to, or none when the prompt no longer shows `displayedId`
    /// (it moved on between the click and the action).
    func targets(for displayedId: FileID, applyToAll: Bool) -> [FileID] {
        current?.id == displayedId ? targets(applyToAll: applyToAll) : []
    }

    func targets(applyToAll: Bool) -> [FileID] {
        applyToAll ? items.map(\.id) : current.map { [$0.id] } ?? []
    }
}
