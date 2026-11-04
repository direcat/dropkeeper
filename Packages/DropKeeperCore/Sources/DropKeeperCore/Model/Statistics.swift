import Foundation

/// Aggregate counters over the stored records (the retention window is what the store holds).
public struct Statistics: Sendable, Equatable {
    public var movedToTrash: Int
    public var deletedPermanently: Int
    public var kept: Int
    public var scheduledByRules: Int
    public var duplicatesDeleted: Int
    public var bytesFreed: Int64

    /// Decisions made: files trashed, deleted permanently or kept.
    public var handled: Int { movedToTrash + deletedPermanently + kept }

    public static let zero = Statistics(
        movedToTrash: 0, deletedPermanently: 0, kept: 0, scheduledByRules: 0, duplicatesDeleted: 0, bytesFreed: 0)

    public init(
        movedToTrash: Int, deletedPermanently: Int, kept: Int, scheduledByRules: Int, duplicatesDeleted: Int,
        bytesFreed: Int64
    ) {
        self.movedToTrash = movedToTrash
        self.deletedPermanently = deletedPermanently
        self.kept = kept
        self.scheduledByRules = scheduledByRules
        self.duplicatesDeleted = duplicatesDeleted
        self.bytesFreed = bytesFreed
    }
}
