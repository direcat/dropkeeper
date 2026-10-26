import Foundation
import Testing

@testable import DropKeeperCore

@Suite(.serialized) struct LiveFileSystemTests {
    let fs = LiveFileSystem()

    @Test func statReportsInodeSizeAndDates() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("a.txt", contents: "hello")
        let st = try #require(fs.stat(file))
        #expect(st.size == 5)
        #expect(!st.isDirectory)
        #expect(st.inode > 0)
        #expect(!st.volumeId.isEmpty)
        #expect(st.addedDate != nil || st.creationDate != nil)
        #expect(fs.stat(dir.path)?.isDirectory == true)
        #expect(fs.stat(dir.path + "/missing") == nil)
    }

    @Test func xattrRoundTrip() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("a.txt")
        #expect(fs.readXattr("net.direcat.dropkeeper.id", at: file) == nil)
        try fs.writeXattr("net.direcat.dropkeeper.id", value: "ABC", at: file)
        #expect(fs.readXattr("net.direcat.dropkeeper.id", at: file) == "ABC")
        try fs.removeXattr("net.direcat.dropkeeper.id", at: file)
        try fs.removeXattr("net.direcat.dropkeeper.id", at: file)  // absent → no throw
        #expect(fs.readXattr("net.direcat.dropkeeper.id", at: file) == nil)
    }

    @Test func xattrSurvivesRename() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("a.txt")
        try fs.writeXattr("net.direcat.dropkeeper.id", value: "ABC", at: file)
        let renamed = dir.path + "/b.txt"
        try fs.moveItem(from: file, to: renamed)
        #expect(fs.readXattr("net.direcat.dropkeeper.id", at: renamed) == "ABC")
    }

    @Test func findsPathByInodeAfterRename() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("a.txt")
        let inode = try #require(fs.stat(file)).inode
        try FileManager.default.createDirectory(atPath: dir.path + "/sub", withIntermediateDirectories: false)
        let renamed = dir.path + "/sub/renamed.txt"
        try fs.moveItem(from: file, to: renamed)
        #expect(fs.path(forInode: inode, onVolumeOf: dir.path) == renamed)
    }

    @Test func tags() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("a.txt")
        try fs.setTag("Temporary", present: true, at: file)
        #expect(fs.tags(at: file).contains("Temporary"))
        try fs.setTag("Temporary", present: false, at: file)
        #expect(!fs.tags(at: file).contains("Temporary"))
    }

    @Test func trashAndRestore() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let file = dir.createFile("trash-me-\(UUID().uuidString).txt")
        let trashed = try fs.moveToTrash(file)
        #expect(fs.stat(file) == nil)
        #expect(fs.stat(trashed) != nil)
        try fs.moveItem(from: trashed, to: file)
        #expect(fs.stat(file) != nil)
    }

    @Test func listingMissingDirectoryThrowsNotFound() {
        let path = "/nonexistent-\(UUID())"
        #expect(throws: FileSystemError.notFound(path)) { try fs.contentsOfDirectory(path) }
    }

    @Test func bookmarkResolvesRenamedFolder() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let original = dir.path + "/A"
        try FileManager.default.createDirectory(atPath: original, withIntermediateDirectories: false)
        let data = try #require(fs.bookmark(for: original))
        try fs.moveItem(from: original, to: dir.path + "/B")
        #expect(fs.resolveBookmark(data).map(fs.canonicalPath) == dir.path + "/B")
    }

    @Test func contentsEqualStopsAtDifference() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let chunk = String(repeating: "a", count: 1_048_576)
        let original = dir.createFile("a.bin", contents: chunk + "x" + chunk)
        let same = dir.createFile("same.bin", contents: chunk + "x" + chunk)
        let differs = dir.createFile("differs.bin", contents: chunk + "y" + chunk)
        let shorter = dir.createFile("shorter.bin", contents: chunk + "x")
        #expect(fs.contentsEqual(original, same))
        #expect(!fs.contentsEqual(original, differs))
        #expect(!fs.contentsEqual(original, shorter))
        #expect(!fs.contentsEqual(shorter, original))
    }

    @Test func contentsEqualFalseForMissingFile() throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let original = dir.createFile("a.txt")
        #expect(!fs.contentsEqual(original, dir.path + "/missing"))
        #expect(!fs.contentsEqual(dir.path + "/missing", original))
        #expect(!fs.contentsEqual(dir.path + "/m1", dir.path + "/m2"))
    }
}
