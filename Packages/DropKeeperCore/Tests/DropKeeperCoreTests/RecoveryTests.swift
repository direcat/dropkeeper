import Foundation
import Testing

@testable import DropKeeperCore

private let baseTime = TestTimeSource.base

@Test func rebuildsRecordsFromXattrs() throws {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.mkdir("/fake/D/sub")
    fs.createFile("/fake/D/scheduled.pdf", added: baseTime)
    fs.createFile("/fake/D/sub/kept.zip", added: baseTime)
    fs.createFile("/fake/D/untracked.txt", added: baseTime)
    let expiry = baseTime.addingTimeInterval(3600)
    try fs.writeXattr(ItemActions.idAttribute, value: "S", at: "/fake/D/scheduled.pdf")
    try fs.writeXattr(ItemActions.expiryAttribute, value: ISODate.format(expiry), at: "/fake/D/scheduled.pdf")
    try fs.writeXattr(ItemActions.idAttribute, value: "K", at: "/fake/D/sub/kept.zip")
    let folder = WatchedFolder(
        id: 1, path: "/fake/D", bookmark: nil, volumeId: "VOL-A", addedAt: baseTime,
        baselineEventId: 0, status: .ok)

    let found = Recovery(fs: fs).scan(folders: [folder], now: baseTime).sorted { $0.id < $1.id }

    #expect(found.map(\.id) == ["K", "S"])
    #expect(found[0].state == .kept)
    #expect(found[0].path == "/fake/D/sub/kept.zip")
    #expect(found[1].state == .scheduled)
    #expect(found[1].expiresAt == expiry)
    #expect(found[1].folderId == 1)
}

@Test func duplicatedIdXattrRecoversEveryCopyAsKept() throws {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/original.pdf", added: baseTime)
    fs.createFile("/fake/D/copy.pdf", added: baseTime)
    fs.createFile("/fake/D/single.pdf", added: baseTime)
    let expiry = ISODate.format(baseTime.addingTimeInterval(3600))
    for path in ["/fake/D/original.pdf", "/fake/D/copy.pdf"] {
        try fs.writeXattr(ItemActions.idAttribute, value: "DUP", at: path)
        try fs.writeXattr(ItemActions.expiryAttribute, value: expiry, at: path)
    }
    try fs.writeXattr(ItemActions.idAttribute, value: "S", at: "/fake/D/single.pdf")
    try fs.writeXattr(ItemActions.expiryAttribute, value: expiry, at: "/fake/D/single.pdf")
    let folder = WatchedFolder(
        id: 1, path: "/fake/D", bookmark: nil, volumeId: "VOL-A", addedAt: baseTime,
        baselineEventId: 0, status: .ok)

    let found = Recovery(fs: fs).scan(folders: [folder], now: baseTime)

    let byPath = Dictionary(uniqueKeysWithValues: found.map { ($0.path, $0) })
    #expect(byPath.count == 3)
    #expect(Set(found.map(\.id)).count == 3)
    for path in ["/fake/D/original.pdf", "/fake/D/copy.pdf"] {
        let file = try #require(byPath[path])
        #expect(file.state == .kept)
        #expect(file.expiresAt == nil)
        #expect(file.id != "DUP")
    }
    #expect(byPath["/fake/D/single.pdf"]?.state == .scheduled)
    #expect(byPath["/fake/D/single.pdf"]?.id == "S")
}
