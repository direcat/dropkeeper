import Foundation

public struct FileStat: Sendable, Equatable {
    public var inode: Int64
    public var volumeId: String
    public var size: Int64
    public var isDirectory: Bool
    public var creationDate: Date?
    /// Date the item was added to its parent directory (`addedToDirectoryDate`).
    public var addedDate: Date?

    public init(
        inode: Int64, volumeId: String, size: Int64, isDirectory: Bool, creationDate: Date?, addedDate: Date?
    ) {
        self.inode = inode
        self.volumeId = volumeId
        self.size = size
        self.isDirectory = isDirectory
        self.creationDate = creationDate
        self.addedDate = addedDate
    }
}

public enum FileSystemError: Error, Equatable {
    case notFound(String)
    case noPermission(String)
    case posix(Int32, String)
    case failed(String)
}

/// All filesystem access used by the engine. Paths are absolute POSIX paths.
public protocol FileSystem: Sendable {
    func stat(_ path: String) -> FileStat?
    /// Size of a regular file via a plain `lstat`; nil for anything else (missing, directory, symlink).
    func fileSize(_ path: String) -> Int64?
    func contentsOfDirectory(_ path: String) throws -> [String]
    func readXattr(_ name: String, at path: String) -> String?
    func hasXattr(_ name: String, at path: String) -> Bool
    func writeXattr(_ name: String, value: String, at path: String) throws
    func removeXattr(_ name: String, at path: String) throws
    func setTag(_ tag: String, present: Bool, at path: String) throws
    func tags(at path: String) -> [String]
    func moveToTrash(_ path: String) throws -> String
    func removeItem(_ path: String) throws
    func moveItem(from: String, to: String) throws
    func path(forInode inode: Int64, onVolumeOf referencePath: String) -> String?
    /// True when both files can be read and hold identical bytes; any open/read error yields false.
    func contentsEqual(_ first: String, _ second: String) -> Bool
    func canonicalPath(_ path: String) -> String
    func bookmark(for path: String) -> Data?
    func resolveBookmark(_ data: Data) -> String?
}
