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

    /// Writes the file in place (not atomically), so FSEvents reports a genuine create
    /// on this path rather than a temp-file rename, like a browser writing a download.
    @discardableResult
    func createFile(_ name: String, contents: String = "x") -> String {
        let filePath = path + "/" + name
        try? Data(contents.utf8).write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
