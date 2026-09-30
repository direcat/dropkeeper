import Foundation

public struct Maintenance: Sendable {
    public static let historyStates: [FileState] = [.kept, .trashed, .gone, .failed]

    let store: FileStore

    public init(store: FileStore) {
        self.store = store
    }

    /// Deletes history older than the retention period. Active records are never touched.
    public func run(retention: HistoryRetention, now: Date) throws -> Int {
        guard let interval = retention.interval else { return 0 }
        let deleted = try store.deleteFiles(in: Self.historyStates, updatedBefore: now.addingTimeInterval(-interval))
        try store.optimize(vacuum: deleted > 0)
        return deleted
    }

    public func clearHistory() throws -> Int {
        let deleted = try store.deleteFiles(in: Self.historyStates, updatedBefore: .distantFuture)
        try store.optimize(vacuum: deleted > 0)
        return deleted
    }
}
