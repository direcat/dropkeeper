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
