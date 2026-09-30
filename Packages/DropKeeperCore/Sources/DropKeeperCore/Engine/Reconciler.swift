import Foundation

public enum ReconcileOutcome: Sendable, Equatable {
    case unchanged, moved, kept, gone
}

/// Brings one record in line with the filesystem. Pure with respect to the store.
public struct Reconciler: Sendable {
    let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func reconcile(_ file: inout TrackedFile, folders: [WatchedFolder], now: Date) -> ReconcileOutcome {
        if let stat = fs.stat(file.path) {
            if stat.inode == file.inode && stat.volumeId == file.volumeId {
                return place(&file, at: file.path, folders: folders, now: now, identityChanged: false)
            }
            if fs.readXattr(ItemActions.idAttribute, at: file.path) == file.id {
                file.inode = stat.inode
                file.volumeId = stat.volumeId
                return place(&file, at: file.path, folders: folders, now: now, identityChanged: true)
            }
        }
        let reference =
            folders.first { $0.id == file.folderId }?.path
            ?? (file.path as NSString).deletingLastPathComponent
        if let newPath = fs.path(forInode: file.inode, onVolumeOf: reference),
            let stat = fs.stat(newPath), stat.volumeId == file.volumeId
        {
            return place(&file, at: newPath, folders: folders, now: now, identityChanged: false)
        }
        file.state = .gone
        file.expiresAt = nil
        file.updatedAt = now
        return .gone
    }

    /// The item was observed at `path` (via an event) and identified as `file`.
    public func adopt(
        path: String, stat: FileStat, file: inout TrackedFile, folders: [WatchedFolder], now: Date
    ) -> ReconcileOutcome {
        var changed = false
        if stat.inode != file.inode || stat.volumeId != file.volumeId {
            file.inode = stat.inode
            file.volumeId = stat.volumeId
            changed = true
        }
        if file.state == .trashed || file.state == .gone {
            file.state = .kept
            file.expiresAt = nil
            file.trashPath = nil
            changed = true
        }
        return place(&file, at: path, folders: folders, now: now, identityChanged: changed)
    }

    private func place(
        _ file: inout TrackedFile, at path: String, folders: [WatchedFolder], now: Date, identityChanged: Bool
    ) -> ReconcileOutcome {
        let moved = path != file.path
        if moved {
            file.path = path
            file.displayName = (path as NSString).lastPathComponent
        }
        guard let folder = folders.first(where: { $0.contains(path) }) else {
            if file.state.isActive {
                file.state = .kept
                file.expiresAt = nil
                file.updatedAt = now
                return .kept
            }
            if moved || identityChanged { file.updatedAt = now }
            return moved || identityChanged ? .moved : .unchanged
        }
        let folderChanged = folder.id != file.folderId
        file.folderId = folder.id
        guard moved || folderChanged || identityChanged else { return .unchanged }
        file.updatedAt = now
        return .moved
    }
}
