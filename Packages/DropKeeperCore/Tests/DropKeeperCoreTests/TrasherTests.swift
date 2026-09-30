import Foundation
import Testing

@testable import DropKeeperCore

private let baseTime = TestTimeSource.base

private func scheduled(_ fs: FakeFileSystem) -> TrackedFile {
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/a.pdf", added: baseTime)
    var file = TrackedFile.new(path: "/fake/D/a.pdf", stat: fs.stat("/fake/D/a.pdf")!, folderId: 1, now: baseTime)
    ItemActions(fs: fs).schedule(&file, duration: 60, now: baseTime, tagEnabled: false)
    return file
}

@Test func trashModeMovesToTrashAndRemembersPath() {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    #expect(Trasher(fs: fs).dispose(&file, mode: .trash, now: baseTime) == .disposed)
    #expect(file.state == .trashed)
    #expect(file.trashPath == FakeFileSystem.trashDir + "/a.pdf")
    #expect(fs.trashedPaths == ["/fake/D/a.pdf"])
}

@Test func permanentModeRemoves() {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    #expect(Trasher(fs: fs).dispose(&file, mode: .permanent, now: baseTime) == .disposed)
    #expect(file.trashPath == nil)
    #expect(fs.removedPaths == ["/fake/D/a.pdf"])
}

@Test func reviewFocusTrashFailuresRetryThenFailWithoutPermanentDelete() {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    fs.failingTrashCount = 10
    let trasher = Trasher(fs: fs)
    var now = baseTime
    for delay in Trasher.retryDelays {
        #expect(trasher.dispose(&file, mode: .trash, now: now) == .retryScheduled)
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == now.addingTimeInterval(delay))
        now = file.expiresAt!
    }
    #expect(trasher.dispose(&file, mode: .trash, now: now) == .failed)
    #expect(file.state == .failed)
    #expect(fs.exists("/fake/D/a.pdf"))
    #expect(fs.removedPaths.isEmpty)
}

@Test func undoRestoresToOriginalPath() throws {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    let trasher = Trasher(fs: fs)
    _ = trasher.dispose(&file, mode: .trash, now: baseTime)
    try trasher.undo(&file, now: baseTime)
    #expect(file.state == .kept)
    #expect(file.path == "/fake/D/a.pdf")
    #expect(fs.exists("/fake/D/a.pdf"))
}

@Test func undoUsesUniqueNameOnCollision() throws {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    let trasher = Trasher(fs: fs)
    _ = trasher.dispose(&file, mode: .trash, now: baseTime)
    fs.createFile("/fake/D/a.pdf", added: baseTime)
    fs.createFile("/fake/D/a 2.pdf", added: baseTime)
    try trasher.undo(&file, now: baseTime)
    #expect(file.path == "/fake/D/a 3.pdf")
    #expect(file.displayName == "a 3.pdf")
}

@Test func undoRejectsNonTrashed() {
    let fs = FakeFileSystem()
    var file = scheduled(fs)
    #expect(throws: TrasherError.notUndoable) { try Trasher(fs: fs).undo(&file, now: baseTime) }
}
