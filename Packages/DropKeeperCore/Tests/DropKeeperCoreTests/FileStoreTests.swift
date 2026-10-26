import Foundation
import GRDB
import Testing

@testable import DropKeeperCore

private let baseDate = TestTimeSource.base

private func sampleFile(
    id: String = UUID().uuidString, state: FileState = .pending, folderId: Int64? = nil,
    inode: Int64 = 42, path: String = "/fake/D/a.pdf", updatedAt: Date = baseDate
) -> TrackedFile {
    TrackedFile(
        id: id, folderId: folderId, path: path, inode: inode, volumeId: "VOL-A", displayName: "a.pdf",
        kind: .document, sizeBytes: 10, state: state, firstSeen: baseDate, expiresAt: nil, trashPath: nil,
        failureCount: 0, updatedAt: updatedAt)
}

private func sampleFolder(_ path: String = "/fake/D") -> WatchedFolder {
    WatchedFolder(
        id: nil, path: path, bookmark: nil, volumeId: "VOL-A", addedAt: baseDate, baselineEventId: 7, status: .ok)
}

@Test func folderCRUD() throws {
    let store = try FileStore.inMemory()
    var folder = try store.insertFolder(sampleFolder())
    #expect(folder.id != nil)
    folder.status = .noAccess
    try store.updateFolder(folder)
    #expect(try store.folders() == [folder])
    try store.deleteFolder(id: folder.id!)
    #expect(try store.folders().isEmpty)
}

@Test func fileRoundTripAndQueries() throws {
    let store = try FileStore.inMemory()
    let folder = try store.insertFolder(sampleFolder())
    var fileA = sampleFile(id: "A", state: .pending, folderId: folder.id)
    let fileB = sampleFile(id: "B", state: .kept, folderId: folder.id, inode: 43, path: "/fake/D/b.pdf")
    try store.insert(fileA)
    try store.insert(fileB)
    #expect(try store.file(id: "A") == fileA)
    fileA.state = .scheduled
    fileA.expiresAt = baseDate.addingTimeInterval(60)
    try store.update(fileA)
    #expect(try store.files(in: [.scheduled]).map(\.id) == ["A"])
    #expect(try store.files(in: [.scheduled], path: "/fake/D/a.pdf").map(\.id) == ["A"])
    #expect(try store.files(in: [.kept], folderId: folder.id!).map(\.id) == ["B"])
    #expect(try store.file(inode: 43, volumeId: "VOL-A", excluding: [.gone])?.id == "B")
    #expect(try store.file(inode: 43, volumeId: "VOL-A", excluding: [.kept]) == nil)
}

@Test func deletingFolderNullsFileReference() throws {
    let store = try FileStore.inMemory()
    let folder = try store.insertFolder(sampleFolder())
    try store.insert(sampleFile(id: "A", state: .kept, folderId: folder.id))
    try store.deleteFolder(id: folder.id!)
    #expect(try store.file(id: "A")?.folderId == nil)
}

@Test func deleteFilesByStateAndAge() throws {
    let store = try FileStore.inMemory()
    try store.insert(sampleFile(id: "old-kept", state: .kept, updatedAt: baseDate))
    try store.insert(sampleFile(id: "new-kept", state: .kept, updatedAt: baseDate.addingTimeInterval(1000)))
    try store.insert(sampleFile(id: "old-pending", state: .pending, updatedAt: baseDate))
    let deleted = try store.deleteFiles(in: [.kept], updatedBefore: baseDate.addingTimeInterval(10))
    #expect(deleted == 1)
    #expect(try store.file(id: "old-kept") == nil)
    #expect(try store.file(id: "new-kept") != nil)
    #expect(try store.file(id: "old-pending") != nil)
}

@Test func settingsDefaultAndSave() throws {
    let store = try FileStore.inMemory()
    #expect(try store.settings() == Settings())
    var newSettings = Settings()
    newSettings.quietMode = true
    try store.saveSettings(newSettings)
    #expect(try store.settings().quietMode)
}

@Test func metaRoundTrip() throws {
    let store = try FileStore.inMemory()
    #expect(try store.meta(.lastEventId) == nil)
    try store.setMeta(.lastEventId, "123")
    #expect(try store.meta(.lastEventId) == "123")
    try store.setMeta(.lastEventId, nil)
    #expect(try store.meta(.lastEventId) == nil)
}

@Test func fileDatabaseUsesIncrementalAutoVacuumAndReportsNew() throws {
    let dir = try TempDir()
    defer { dir.cleanup() }
    let url = URL(fileURLWithPath: dir.path + "/dropkeeper.sqlite")
    let first = try FileStore.open(at: url)
    #expect(first.isNew)
    #expect(!first.recoveredFromCorruption)
    #expect(try first.store.autoVacuumMode() == 2)
    try first.store.optimize(vacuum: true)
    let second = try FileStore.open(at: url)
    #expect(!second.isNew)
}

@Test func corruptDatabaseIsMovedAsideAndRecreated() throws {
    let dir = try TempDir()
    defer { dir.cleanup() }
    let path = dir.path + "/dropkeeper.sqlite"
    FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x42, count: 4096))
    let result = try FileStore.open(at: URL(fileURLWithPath: path), now: baseDate)
    #expect(result.recoveredFromCorruption)
    #expect(try result.store.folders().isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("dropkeeper.sqlite.corrupt-") })
}

@Test func migrationV2AddsNullableColumns() throws {
    let store = try FileStore.inMemory()
    var withFields = sampleFile(id: "A")
    withFields.scheduleDuration = 3600
    withFields.duplicateOf = "report.pdf"
    try store.insert(withFields)
    try store.insert(sampleFile(id: "B", inode: 43, path: "/fake/D/b.pdf"))
    #expect(try store.file(id: "A") == withFields)
    #expect(try store.file(id: "B")?.scheduleDuration == nil)
    #expect(try store.file(id: "B")?.duplicateOf == nil)
}

@Test func populatedV1DatabaseMigratesToV2() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("dropkeeper.sqlite")
    // The schema exactly as the v1 migration creates it, plus GRDB's bookkeeping row for "v1".
    let legacy = try DatabaseQueue(path: url.path)
    try legacy.write { db in
        try db.execute(
            sql: """
                CREATE TABLE watched_folder (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, bookmark BLOB,
                    volume_id TEXT NOT NULL, added_at DATETIME NOT NULL, baseline_event_id INTEGER NOT NULL,
                    status TEXT NOT NULL);
                CREATE TABLE tracked_file (
                    id TEXT PRIMARY KEY NOT NULL, folder_id INTEGER REFERENCES watched_folder(id) ON DELETE SET NULL,
                    path TEXT NOT NULL, inode INTEGER NOT NULL, volume_id TEXT NOT NULL, display_name TEXT NOT NULL,
                    kind TEXT NOT NULL, size_bytes INTEGER, state TEXT NOT NULL, first_seen DATETIME NOT NULL,
                    expires_at DATETIME, trash_path TEXT, failure_count INTEGER NOT NULL DEFAULT 0,
                    updated_at DATETIME NOT NULL);
                CREATE INDEX tracked_file_state_expires ON tracked_file(state, expires_at);
                CREATE INDEX tracked_file_identity ON tracked_file(inode, volume_id);
                CREATE INDEX tracked_file_state_updated ON tracked_file(state, updated_at);
                CREATE INDEX tracked_file_folder ON tracked_file(folder_id);
                CREATE INDEX tracked_file_path ON tracked_file(path);
                CREATE TABLE setting (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1');
                """)
        try db.execute(
            sql: """
                INSERT INTO tracked_file (id, path, inode, volume_id, display_name, kind, size_bytes, state,
                    first_seen, failure_count, updated_at)
                VALUES ('OLD', '/fake/D/old.pdf', 7, 'VOL-A', 'old.pdf', 'document', 10, 'pending',
                    '2026-01-01 00:00:00.000', 0, '2026-01-01 00:00:00.000')
                """)
    }
    try legacy.close()
    let result = try FileStore.open(at: url)
    let file = try #require(try result.store.file(id: "OLD"))
    #expect(file.path == "/fake/D/old.pdf")
    #expect(file.state == .pending)
    #expect(file.sizeBytes == 10)
    #expect(file.scheduleDuration == nil)
    #expect(file.duplicateOf == nil)
    #expect(!result.recoveredFromCorruption)
}
