import Foundation
import Testing

@testable import DropKeeperCore

private let baseTime = TestTimeSource.base
private let year: TimeInterval = 365 * 86_400

private func record(_ id: String, _ state: FileState, age: TimeInterval) -> TrackedFile {
    TrackedFile(
        id: id, folderId: nil, path: "/fake/D/\(id)", inode: 1, volumeId: "V", displayName: id, kind: .other,
        sizeBytes: 1, state: state, firstSeen: baseTime, expiresAt: nil, trashPath: nil, failureCount: 0,
        updatedAt: baseTime.addingTimeInterval(-age))
}

@Test func deletesOnlyOldHistoryNeverActive() throws {
    let store = try FileStore.inMemory()
    for state in FileState.allCases {
        try store.insert(record("old-\(state)", state, age: year + 86_400))
        try store.insert(record("new-\(state)", state, age: 86_400))
    }
    let deleted = try Maintenance(store: store).run(retention: .oneYear, now: baseTime)
    #expect(deleted == 4)
    let remaining = Set(try store.files(in: FileState.allCases).map(\.id))
    #expect(remaining.contains("old-pending"))
    #expect(remaining.contains("old-scheduled"))
    #expect(!remaining.contains("old-kept"))
    #expect(!remaining.contains("old-failed"))
    #expect(remaining.contains("new-trashed"))
}

@Test func foreverKeepsEverything() throws {
    let store = try FileStore.inMemory()
    try store.insert(record("ancient", .trashed, age: 10 * year))
    #expect(try Maintenance(store: store).run(retention: .forever, now: baseTime) == 0)
    #expect(try store.file(id: "ancient") != nil)
}

@Test func clearHistoryRemovesAllInactive() throws {
    let store = try FileStore.inMemory()
    try store.insert(record("a", .kept, age: 0))
    try store.insert(record("b", .scheduled, age: 0))
    #expect(try Maintenance(store: store).clearHistory() == 1)
    #expect(try store.file(id: "b") != nil)
}
