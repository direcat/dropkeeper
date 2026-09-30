import Foundation
import Synchronization

@testable import DropKeeperCore

final class FakeFileSystem: FileSystem {
    static let trashDir = "/fake/.Trash"

    struct Entry: Sendable {
        var inode: Int64
        var volume: String
        var size: Int64
        var isDirectory: Bool
        var added: Date?
        var xattrs: [String: String] = [:]
        var tags: [String] = []
    }

    struct State: Sendable {
        var entries: [String: Entry] = [:]
        var nextInode: Int64 = 1000
        var failingTrashCount = 0
        var deniedDirectories: Set<String> = []
        var trashedPaths: [String] = []
        var removedPaths: [String] = []
    }

    private let state = Mutex(State())

    init() {
        mkdir(Self.trashDir)
    }

    // MARK: Test helpers

    func mkdir(_ path: String, volume: String = "VOL-A", added: Date? = nil) {
        state.withLock { state in
            state.nextInode += 1
            state.entries[path] = Entry(
                inode: state.nextInode, volume: volume, size: 0, isDirectory: true, added: added)
        }
    }

    @discardableResult
    func createFile(_ path: String, size: Int64 = 100, added: Date?, volume: String = "VOL-A") -> Int64 {
        state.withLock { state in
            state.nextInode += 1
            state.entries[path] = Entry(
                inode: state.nextInode, volume: volume, size: size, isDirectory: false, added: added)
            return state.nextInode
        }
    }

    func setSize(_ path: String, _ size: Int64) {
        state.withLock { $0.entries[path]?.size = size }
    }

    func move(_ from: String, _ to: String, toVolume: String? = nil) {
        state.withLock { state in
            let moved = state.entries.keys.filter { $0 == from || $0.hasPrefix(from + "/") }
            for old in moved {
                guard var entry = state.entries.removeValue(forKey: old) else { continue }
                if let toVolume {
                    state.nextInode += 1
                    entry.inode = state.nextInode
                    entry.volume = toVolume
                }
                state.entries[to + old.dropFirst(from.count)] = entry
            }
        }
    }

    func delete(_ path: String) {
        state.withLock { state in
            for key in state.entries.keys where key == path || key.hasPrefix(path + "/") {
                state.entries.removeValue(forKey: key)
            }
        }
    }

    func exists(_ path: String) -> Bool { state.withLock { $0.entries[path] != nil } }
    func xattr(_ name: String, at path: String) -> String? { readXattr(name, at: path) }

    var failingTrashCount: Int {
        get { state.withLock { $0.failingTrashCount } }
        set { state.withLock { $0.failingTrashCount = newValue } }
    }
    var deniedDirectories: Set<String> {
        get { state.withLock { $0.deniedDirectories } }
        set { state.withLock { $0.deniedDirectories = newValue } }
    }
    var trashedPaths: [String] { state.withLock { $0.trashedPaths } }
    var removedPaths: [String] { state.withLock { $0.removedPaths } }

    // MARK: FileSystem

    func stat(_ path: String) -> FileStat? {
        state.withLock { state in
            state.entries[path].map {
                FileStat(
                    inode: $0.inode, volumeId: $0.volume, size: $0.size, isDirectory: $0.isDirectory,
                    creationDate: $0.added, addedDate: $0.added)
            }
        }
    }

    func contentsOfDirectory(_ path: String) throws -> [String] {
        try state.withLock { state in
            if state.deniedDirectories.contains(path) { throw FileSystemError.noPermission(path) }
            guard state.entries[path]?.isDirectory == true else { throw FileSystemError.notFound(path) }
            return state.entries.keys.compactMap { key in
                guard key.hasPrefix(path + "/") else { return nil }
                let rest = key.dropFirst(path.count + 1)
                return rest.contains("/") ? nil : String(rest)
            }
        }
    }

    func readXattr(_ name: String, at path: String) -> String? {
        state.withLock { $0.entries[path]?.xattrs[name] }
    }

    func writeXattr(_ name: String, value: String, at path: String) throws {
        try state.withLock { state in
            guard state.entries[path] != nil else { throw FileSystemError.notFound(path) }
            state.entries[path]?.xattrs[name] = value
        }
    }

    func removeXattr(_ name: String, at path: String) throws {
        try state.withLock { state in
            guard state.entries[path] != nil else { throw FileSystemError.notFound(path) }
            state.entries[path]?.xattrs[name] = nil
        }
    }

    func setTag(_ tag: String, present: Bool, at path: String) throws {
        try state.withLock { state in
            guard var entry = state.entries[path] else { throw FileSystemError.notFound(path) }
            entry.tags.removeAll { $0 == tag }
            if present { entry.tags.append(tag) }
            state.entries[path] = entry
        }
    }

    func tags(at path: String) -> [String] { state.withLock { $0.entries[path]?.tags ?? [] } }

    func moveToTrash(_ path: String) throws -> String {
        let shouldFail = state.withLock { state -> Bool in
            guard state.failingTrashCount > 0 else { return false }
            state.failingTrashCount -= 1
            return true
        }
        if shouldFail { throw FileSystemError.failed("injected trash failure") }
        guard exists(path) else { throw FileSystemError.notFound(path) }
        let target = Self.trashDir + "/" + (path as NSString).lastPathComponent
        move(path, target)
        state.withLock { $0.trashedPaths.append(path) }
        return target
    }

    func removeItem(_ path: String) throws {
        guard exists(path) else { throw FileSystemError.notFound(path) }
        delete(path)
        state.withLock { $0.removedPaths.append(path) }
    }

    func moveItem(from: String, to: String) throws {
        guard exists(from) else { throw FileSystemError.notFound(from) }
        guard !exists(to) else { throw FileSystemError.failed("exists: \(to)") }
        move(from, to)
    }

    func path(forInode inode: Int64, onVolumeOf referencePath: String) -> String? {
        state.withLock { state in
            guard let volume = state.entries[referencePath]?.volume else { return nil }
            return state.entries.first { $0.value.inode == inode && $0.value.volume == volume }?.key
        }
    }

    func canonicalPath(_ path: String) -> String { path }
    func bookmark(for path: String) -> Data? { Data(path.utf8) }
    func resolveBookmark(_ data: Data) -> String? { String(bytes: data, encoding: .utf8) }
}
