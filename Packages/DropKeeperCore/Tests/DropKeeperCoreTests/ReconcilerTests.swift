import Foundation
import Testing

@testable import DropKeeperCore

private let baseTime = TestTimeSource.base
private let downloads = WatchedFolder(
    id: 1, path: "/fake/D", bookmark: nil, volumeId: "VOL-A", addedAt: baseTime,
    baselineEventId: 0, status: .ok)
private let desktop = WatchedFolder(
    id: 2, path: "/fake/Desk", bookmark: nil, volumeId: "VOL-A", addedAt: baseTime,
    baselineEventId: 0, status: .ok)

private func setup() -> (FakeFileSystem, TrackedFile) {
    let fs = FakeFileSystem()
    fs.mkdir("/fake")
    fs.mkdir("/fake/D")
    fs.mkdir("/fake/D/sub")
    fs.mkdir("/fake/Desk")
    fs.mkdir("/fake/Out")
    fs.createFile("/fake/D/a.pdf", added: baseTime)
    var file = TrackedFile.new(path: "/fake/D/a.pdf", stat: fs.stat("/fake/D/a.pdf")!, folderId: 1, now: baseTime)
    ItemActions(fs: fs).schedule(&file, duration: 60, now: baseTime, tagEnabled: false)
    return (fs, file)
}

@Test func unchangedWhenInPlace() {
    let (fs, original) = setup()
    var file = original
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .unchanged)
    #expect(file == original)
}

@Test func renameInsideFolderUpdatesPath() {
    let (fs, original) = setup()
    var file = original
    fs.move("/fake/D/a.pdf", "/fake/D/sub/b.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .moved)
    #expect(file.path == "/fake/D/sub/b.pdf")
    #expect(file.displayName == "b.pdf")
    #expect(file.state == .scheduled)
}

@Test func moveToOtherWatchedFolderKeepsExpiry() {
    let (fs, original) = setup()
    var file = original
    fs.move("/fake/D/a.pdf", "/fake/Desk/a.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads, desktop], now: baseTime) == .moved)
    #expect(file.folderId == 2)
    #expect(file.expiresAt == original.expiresAt)
}

@Test func moveOutsideWatchedFoldersMeansKept() {
    let (fs, original) = setup()
    var file = original
    fs.move("/fake/D/a.pdf", "/fake/Out/a.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .kept)
    #expect(file.state == .kept)
    #expect(file.expiresAt == nil)
    #expect(file.path == "/fake/Out/a.pdf")
}

@Test func reviewFocusDeletedOrCrossVolumeMoveIsGone() {
    let (fs, original) = setup()
    var deleted = original
    fs.delete("/fake/D/a.pdf")
    #expect(Reconciler(fs: fs).reconcile(&deleted, folders: [downloads], now: baseTime) == .gone)
    #expect(deleted.state == .gone)

    let (fs2, original2) = setup()
    fs2.mkdir("/fake/Ext", volume: "VOL-B")
    var moved = original2
    fs2.move("/fake/D/a.pdf", "/fake/Ext/a.pdf", toVolume: "VOL-B")
    #expect(Reconciler(fs: fs2).reconcile(&moved, folders: [downloads], now: baseTime) == .gone)
}

@Test func replacedInPlaceWithSameIdAdoptsNewInode() {
    let (fs, original) = setup()
    var file = original
    fs.delete("/fake/D/a.pdf")
    fs.createFile("/fake/D/a.pdf", added: baseTime)
    try? fs.writeXattr(ItemActions.idAttribute, value: file.id, at: "/fake/D/a.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .moved)
    #expect(file.inode == fs.stat("/fake/D/a.pdf")!.inode)
}

@Test func adoptRestoresTrashedRecordAsKept() {
    let (fs, original) = setup()
    var file = original
    file.state = .trashed
    file.trashPath = "/fake/.Trash/a.pdf"
    let stat = fs.stat("/fake/D/a.pdf")!
    #expect(
        Reconciler(fs: fs).adopt(path: "/fake/D/a.pdf", stat: stat, file: &file, folders: [downloads], now: baseTime)
            == .moved)
    #expect(file.state == .kept)
    #expect(file.trashPath == nil)
}

@Test func adoptAtNewPath() {
    let (fs, original) = setup()
    var file = original
    fs.move("/fake/D/a.pdf", "/fake/D/c.pdf")
    let stat = fs.stat("/fake/D/c.pdf")!
    #expect(
        Reconciler(fs: fs).adopt(path: "/fake/D/c.pdf", stat: stat, file: &file, folders: [downloads], now: baseTime)
            == .moved)
    #expect(file.path == "/fake/D/c.pdf")
}

@Test func candidateWithDifferentIdXattrIsGone() {
    let (fs, original) = setup()
    var file = original
    fs.move("/fake/D/a.pdf", "/fake/D/sub/b.pdf")
    try? fs.writeXattr(ItemActions.idAttribute, value: "other-id", at: "/fake/D/sub/b.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .gone)
    #expect(file.state == .gone)
}

@Test func sameInodeWithDifferentIdXattrIsNotInPlace() {
    let (fs, original) = setup()
    var file = original
    try? fs.writeXattr(ItemActions.idAttribute, value: "other-id", at: "/fake/D/a.pdf")
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .gone)
}

@Test func inactiveRecordIsReturnedUnchanged() {
    let (fs, original) = setup()
    var file = original
    file.state = .trashed
    file.trashPath = "/fake/.Trash/a.pdf"
    fs.delete("/fake/D/a.pdf")
    let before = file
    #expect(Reconciler(fs: fs).reconcile(&file, folders: [downloads], now: baseTime) == .unchanged)
    #expect(file == before)
}
