import Foundation

/// Rebuilds records from xattrs after the database was lost.
public struct Recovery: Sendable {
    public static let maxDepth = 4

    let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func scan(folders: [WatchedFolder], now: Date) -> [TrackedFile] {
        var found: [TrackedFile] = []
        for folder in folders {
            walk(folder.path, depth: 0, folder: folder, now: now, into: &found)
        }
        return resolvingDuplicates(found)
    }

    /// An id on more than one path (a copy made outside DropKeeper) cannot tell which path the user
    /// scheduled: every such path is recovered as `kept` under a fresh id, never as `scheduled`.
    private func resolvingDuplicates(_ found: [TrackedFile]) -> [TrackedFile] {
        let counts = Dictionary(grouping: found, by: \.id).mapValues(\.count)
        return found.map { file in
            guard counts[file.id, default: 0] > 1 else { return file }
            var copy = file
            copy.id = UUID().uuidString
            copy.state = .kept
            copy.expiresAt = nil
            return copy
        }
    }

    private func walk(
        _ directory: String, depth: Int, folder: WatchedFolder, now: Date, into found: inout [TrackedFile]
    ) {
        guard depth < Self.maxDepth, let names = try? fs.contentsOfDirectory(directory) else { return }
        for name in names where !name.hasPrefix(".") {
            let path = directory + "/" + name
            guard let stat = fs.stat(path) else { continue }
            if let id = fs.readXattr(ItemActions.idAttribute, at: path) {
                var file = TrackedFile.new(path: path, stat: stat, folderId: folder.id, now: now)
                file.id = id
                if let raw = fs.readXattr(ItemActions.expiryAttribute, at: path), let expiry = ISODate.parse(raw) {
                    file.state = .scheduled
                    file.expiresAt = expiry
                } else {
                    file.state = .kept
                }
                found.append(file)
            } else if stat.isDirectory {
                walk(path, depth: depth + 1, folder: folder, now: now, into: &found)
            }
        }
    }
}
