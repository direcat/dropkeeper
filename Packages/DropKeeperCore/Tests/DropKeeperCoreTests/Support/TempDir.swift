import Foundation

@testable import DropKeeperCore

/// Real directory for integration tests, under ~/Library/Caches so FSEvents history covers it.
struct TempDir {
    let path: String

    init() throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("DropKeeperTests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = LiveFileSystem().canonicalPath(url.path)
    }

    @discardableResult
    func createFile(_ name: String, contents: String = "x") -> String {
        let filePath = path + "/" + name
        FileManager.default.createFile(atPath: filePath, contents: Data(contents.utf8))
        return filePath
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
