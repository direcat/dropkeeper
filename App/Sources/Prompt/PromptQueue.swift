import DropKeeperCore

/// Pending files waiting for a decision, oldest first, minus the ones the user closed the prompt for.
/// Scheduled files reopened from a rule notice (`revisiting`) go in front of them, one at a time.
struct PromptQueue: Equatable {
    private(set) var items: [TrackedFile] = []
    private(set) var revisiting: [TrackedFile] = []
    private var dismissed: Set<FileID> = []

    var current: TrackedFile? { revisiting.first ?? items.first }
    var isRevisiting: Bool { !revisiting.isEmpty }

    /// `scheduled` refreshes the revisited records and drops the ones that are no longer scheduled.
    mutating func update(pending: [TrackedFile], scheduled: [TrackedFile]) {
        let scheduledById = Dictionary(scheduled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        revisiting = revisiting.compactMap { scheduledById[$0.id] }
        let pendingIds = Set(pending.map(\.id))
        dismissed.formIntersection(pendingIds)
        let visible = pending.filter { !dismissed.contains($0.id) }
        // Keep the current file first so the prompt does not jump when new files arrive.
        if let first = items.first, let kept = visible.first(where: { $0.id == first.id }) {
            items = [kept] + visible.filter { $0.id != first.id }
        } else {
            items = visible
        }
    }

    /// Shows these scheduled files first, to change their timer. They stay scheduled until a decision is made.
    mutating func revisit(_ files: [TrackedFile]) {
        revisiting = files
    }

    /// Closes the prompt for the current file (or the whole stack) without deciding. Closing a revisit leaves
    /// the rule's expiry and the pending files alone.
    mutating func dismiss(applyToAll: Bool) {
        dismiss(ids: targets(applyToAll: applyToAll))
    }

    /// Hides these files until they leave the pending list (e.g. right after a successful decision).
    mutating func dismiss(ids: [FileID]) {
        dismissed.formUnion(ids.filter { id in !revisiting.contains { $0.id == id } })
        revisiting.removeAll { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
    }

    /// Brings these files back (e.g. a file closed with Esc, picked from the list) and shows them first.
    /// Ids that are no longer pending are ignored.
    mutating func restore(ids: [FileID], pending: [TrackedFile]) {
        dismissed.subtract(ids)
        let visible = pending.filter { !dismissed.contains($0.id) }
        let restored = visible.filter { ids.contains($0.id) }
        guard !restored.isEmpty else {
            update(pending: pending, scheduled: revisiting)
            return
        }
        revisiting = []  // the user picked a file: it goes first
        items = restored + visible.filter { !ids.contains($0.id) }
    }

    /// The files an action from the prompt applies to, or none when the prompt no longer shows `displayedId`
    /// (it moved on between the click and the action).
    func targets(for displayedId: FileID, applyToAll: Bool) -> [FileID] {
        current?.id == displayedId ? targets(applyToAll: applyToAll) : []
    }

    func targets(applyToAll: Bool) -> [FileID] {
        applyToAll && !isRevisiting ? items.map(\.id) : current.map { [$0.id] } ?? []
    }
}
