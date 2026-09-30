import Foundation
import Testing

@testable import DropKeeperCore

@Test func fakeRenameKeepsInodeAndXattrs() throws {
    let fake = FakeFileSystem()
    fake.mkdir("/fake/D")
    let inode = fake.createFile("/fake/D/a.txt", added: TestTimeSource.base)
    try fake.writeXattr("k", value: "v", at: "/fake/D/a.txt")
    fake.move("/fake/D/a.txt", "/fake/D/b.txt")
    #expect(fake.stat("/fake/D/a.txt") == nil)
    #expect(fake.stat("/fake/D/b.txt")?.inode == inode)
    #expect(fake.readXattr("k", at: "/fake/D/b.txt") == "v")
    #expect(fake.path(forInode: inode, onVolumeOf: "/fake/D") == "/fake/D/b.txt")
}

@Test func fakeCrossVolumeMoveChangesInodeAndIsNotFoundByInode() {
    let fake = FakeFileSystem()
    fake.mkdir("/fake/D")
    fake.mkdir("/fake/Ext", volume: "VOL-B")
    let inode = fake.createFile("/fake/D/a.txt", added: TestTimeSource.base)
    fake.move("/fake/D/a.txt", "/fake/Ext/a.txt", toVolume: "VOL-B")
    #expect(fake.stat("/fake/Ext/a.txt")?.inode != inode)
    #expect(fake.path(forInode: inode, onVolumeOf: "/fake/D") == nil)
}

@Test func fakeListsDirectChildrenOnly() throws {
    let fake = FakeFileSystem()
    fake.mkdir("/fake/D")
    fake.mkdir("/fake/D/sub")
    fake.createFile("/fake/D/a.txt", added: nil)
    fake.createFile("/fake/D/sub/b.txt", added: nil)
    #expect(try fake.contentsOfDirectory("/fake/D").sorted() == ["a.txt", "sub"])
}

@Test func fakeTrashFailureInjection() throws {
    let fake = FakeFileSystem()
    fake.mkdir("/fake/D")
    fake.createFile("/fake/D/a.txt", added: nil)
    fake.failingTrashCount = 1
    #expect(throws: FileSystemError.self) { try fake.moveToTrash("/fake/D/a.txt") }
    let trashed = try fake.moveToTrash("/fake/D/a.txt")
    #expect(trashed == FakeFileSystem.trashDir + "/a.txt")
    #expect(fake.trashedPaths == ["/fake/D/a.txt"])
}

@Test func fakeDeniedDirectory() {
    let fake = FakeFileSystem()
    fake.mkdir("/fake/D")
    fake.deniedDirectories = ["/fake/D"]
    #expect(throws: FileSystemError.noPermission("/fake/D")) { try fake.contentsOfDirectory("/fake/D") }
}
