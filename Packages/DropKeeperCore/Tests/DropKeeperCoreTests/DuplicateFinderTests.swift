import Foundation
import Testing

@testable import DropKeeperCore

struct DuplicateFinderTests {
    let fs = FakeFileSystem()
    let folder = "/watched"
    let bytes = Data("same bytes".utf8)

    init() {
        fs.mkdir(folder)
    }

    private func find(_ name: String, patterns: [String] = []) -> String? {
        let path = folder + "/" + name
        return DuplicateFinder.find(
            path: path, size: fs.stat(path)?.size ?? 0, folderPath: folder, ignoredPatterns: patterns, fs: fs)
    }

    @Test func findsSameContentUnderAnotherName() {
        fs.createFile(folder + "/report.pdf", content: bytes, added: nil)
        fs.createFile(folder + "/report (1).pdf", content: bytes, added: nil)
        #expect(find("report (1).pdf") == "report.pdf")
    }

    @Test func sameSizeDifferentContentIsNotADuplicate() {
        fs.createFile(folder + "/a.txt", content: Data("aaaa".utf8), added: nil)
        fs.createFile(folder + "/b.txt", content: Data("bbbb".utf8), added: nil)
        #expect(find("b.txt") == nil)
    }

    @Test func ignoresSubfoldersDotfilesAndIgnoredNames() {
        fs.createFile(folder + "/new.dat", content: bytes, added: nil)
        fs.mkdir(folder + "/sub")
        fs.createFile(folder + "/sub/copy.dat", content: bytes, added: nil)
        fs.createFile(folder + "/.hidden", content: bytes, added: nil)
        fs.createFile(folder + "/~$scratch.dat", content: bytes, added: nil)
        #expect(find("new.dat", patterns: IgnorePattern.defaults) == nil)
        fs.createFile(folder + "/old.dat", content: bytes, added: nil)
        #expect(find("new.dat", patterns: IgnorePattern.defaults) == "old.dat")
    }

    @Test func emptyFilesAreNeverDuplicates() {
        fs.createFile(folder + "/a.txt", content: Data(), added: nil)
        fs.createFile(folder + "/b.txt", content: Data(), added: nil)
        #expect(find("b.txt") == nil)
    }

    @Test func firstMatchBySortedNameWins() {
        fs.createFile(folder + "/b.dat", content: bytes, added: nil)
        fs.createFile(folder + "/a.dat", content: bytes, added: nil)
        fs.createFile(folder + "/c.dat", content: bytes, added: nil)
        #expect(find("c.dat") == "a.dat")
    }
}
