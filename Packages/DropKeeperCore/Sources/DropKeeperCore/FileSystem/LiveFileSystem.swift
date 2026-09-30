import Darwin
import Foundation
import Synchronization

public final class LiveFileSystem: FileSystem {
    private let volumeIds = Mutex<[Int32: String]>([:])

    public init() {}

    public func stat(_ path: String) -> FileStat? {
        var st = Darwin.stat()
        guard lstat(path, &st) == 0 else { return nil }
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return FileStat(
            inode: Int64(bitPattern: st.st_ino),
            volumeId: volumeId(device: st.st_dev, path: path),
            size: Int64(st.st_size),
            isDirectory: (st.st_mode & S_IFMT) == S_IFDIR,
            creationDate: values?.creationDate,
            addedDate: values?.addedToDirectoryDate
        )
    }

    private func volumeId(device: Int32, path: String) -> String {
        if let cached = volumeIds.withLock({ $0[device] }) { return cached }
        let uuid =
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]))?
            .volumeUUIDString ?? "dev-\(device)"
        volumeIds.withLock { $0[device] = uuid }
        return uuid
    }

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch let error as CocoaError {
            switch error.code {
            case .fileReadNoPermission: throw FileSystemError.noPermission(path)
            case .fileReadNoSuchFile, .fileNoSuchFile: throw FileSystemError.notFound(path)
            default: throw FileSystemError.failed(error.localizedDescription)
            }
        }
    }

    public func readXattr(_ name: String, at path: String) -> String? {
        let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let read = getxattr(path, name, &buffer, length, 0, XATTR_NOFOLLOW)
        guard read == length else { return nil }
        return String(bytes: buffer, encoding: .utf8)
    }

    public func writeXattr(_ name: String, value: String, at path: String) throws {
        let bytes = Array(value.utf8)
        guard setxattr(path, name, bytes, bytes.count, 0, XATTR_NOFOLLOW) == 0 else {
            throw FileSystemError.posix(errno, path)
        }
    }

    public func removeXattr(_ name: String, at path: String) throws {
        guard removexattr(path, name, XATTR_NOFOLLOW) == 0 || errno == ENOATTR else {
            throw FileSystemError.posix(errno, path)
        }
    }

    public func setTag(_ tag: String, present: Bool, at path: String) throws {
        let url = URL(fileURLWithPath: path)
        var names = tags(at: path)
        if present {
            guard !names.contains(tag) else { return }
            names.append(tag)
        } else {
            guard names.contains(tag) else { return }
            names.removeAll { $0 == tag }
        }
        // `URLResourceValues.tagNames` has no setter before macOS 26; NSURL works on macOS 15.
        try (url as NSURL).setResourceValue(names, forKey: .tagNamesKey)
    }

    public func tags(at path: String) -> [String] {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    public func moveToTrash(_ path: String) throws -> String {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        guard let trashed = resulting?.path else { throw FileSystemError.failed("no trash URL for \(path)") }
        return trashed
    }

    public func removeItem(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    public func moveItem(from: String, to: String) throws {
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    public func path(forInode inode: Int64, onVolumeOf referencePath: String) -> String? {
        var info = statfs()
        guard statfs(referencePath, &info) == 0 else { return nil }
        var fsid = info.f_fsid
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = fsgetpath(&buffer, buffer.count, &fsid, UInt64(bitPattern: inode))
        guard length > 0 else { return nil }
        return canonicalPath(String(cString: buffer))
    }

    public func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func bookmark(for path: String) -> Data? {
        try? URL(fileURLWithPath: path).bookmarkData()
    }

    public func resolveBookmark(_ data: Data) -> String? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).path
    }
}
