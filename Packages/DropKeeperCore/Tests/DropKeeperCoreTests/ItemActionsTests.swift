import Foundation
import Testing

@testable import DropKeeperCore

private func makeFile(_ fs: FakeFileSystem, _ path: String = "/fake/D/a.pdf") -> TrackedFile {
    fs.mkdir("/fake/D")
    fs.createFile(path, added: TestTimeSource.base)
    return TrackedFile.new(path: path, stat: fs.stat(path)!, folderId: 1, now: TestTimeSource.base)
}

@Test func scheduleWritesExpiryIdAndOptionalTag() {
    let fs = FakeFileSystem()
    var file = makeFile(fs)
    let actions = ItemActions(fs: fs)
    actions.markPending(file)
    #expect(fs.xattr(ItemActions.idAttribute, at: file.path) == file.id)
    actions.schedule(&file, duration: 3600, now: TestTimeSource.base, tagEnabled: true)
    #expect(file.state == .scheduled)
    #expect(file.expiresAt == TestTimeSource.base.addingTimeInterval(3600))
    #expect(fs.xattr(ItemActions.expiryAttribute, at: file.path) == ISODate.format(file.expiresAt!))
    #expect(fs.tags(at: file.path) == ["Temporary"])
}

@Test func keepClearsExpiryAndTagButKeepsId() {
    let fs = FakeFileSystem()
    var file = makeFile(fs)
    let actions = ItemActions(fs: fs)
    actions.schedule(&file, duration: 60, now: TestTimeSource.base, tagEnabled: true)
    actions.keep(&file, now: TestTimeSource.base)
    #expect(file.state == .kept)
    #expect(file.expiresAt == nil)
    #expect(fs.xattr(ItemActions.expiryAttribute, at: file.path) == nil)
    #expect(fs.xattr(ItemActions.idAttribute, at: file.path) == file.id)
    #expect(fs.tags(at: file.path).isEmpty)
}

@Test func scheduleRecordsDuration() {
    let fs = FakeFileSystem()
    var file = makeFile(fs)
    let actions = ItemActions(fs: fs)
    actions.schedule(&file, duration: 3600, now: TestTimeSource.base, tagEnabled: false)
    #expect(file.scheduleDuration == 3600)
    actions.keep(&file, now: TestTimeSource.base)
    #expect(file.scheduleDuration == nil)
}

@Test func timerLengthFallsBackForLegacyRecords() {
    let fs = FakeFileSystem()
    var file = makeFile(fs)
    file.state = .scheduled
    file.scheduleDuration = nil
    file.updatedAt = TestTimeSource.base
    file.expiresAt = TestTimeSource.base.addingTimeInterval(7200)
    #expect(file.timerLength == 7200)
    file.scheduleDuration = 60
    #expect(file.timerLength == 60)
    file.state = .kept
    #expect(file.timerLength == nil)
}
