import Foundation

extension DropKeeperEngine {
    // MARK: Folders

    public func addFolder(path: String) throws -> WatchedFolder {
        let canonical = env.fs.canonicalPath(path)
        // Watching the root would sweep every new top-level item on the volume.
        guard canonical != "/" else { throw EngineError.invalidFolder(canonical) }
        if let existing = folders.first(where: { $0.path == canonical }) { return existing }
        guard env.fs.stat(canonical)?.isDirectory == true else { throw EngineError.notADirectory(canonical) }
        if folders.contains(where: { $0.contains(canonical) || WatchedFolder.contains(parent: canonical, $0.path) }) {
            throw EngineError.overlapsExistingFolder(canonical)
        }
        let folder = try insertFolder(path: canonical)
        if try store.meta(.lastEventId) == nil {
            try store.setMeta(.lastEventId, String(folder.baselineEventId))
        }
        refreshFolderStatuses()
        notify.yield(.foldersChanged)
        if isRunning { restartWatcher() }
        return folders.first { $0.id == folder.id } ?? folder
    }

    func insertFolder(path: String) throws -> WatchedFolder {
        let folder = WatchedFolder(
            id: nil, path: path, bookmark: env.fs.bookmark(for: path), volumeId: env.fs.stat(path)?.volumeId ?? "",
            addedAt: env.time.now(), baselineEventId: env.currentEventId(), status: .ok)
        let inserted = try store.insertFolder(folder)
        folders = try store.folders()
        return inserted
    }

    func folder(containing path: String) -> WatchedFolder? {
        folders.first { $0.status == .ok && $0.contains(path) }
    }

    func isFolderAvailable(_ id: Int64?) -> Bool {
        guard let id else { return true }
        return folders.first { $0.id == id }?.status == .ok
    }

    /// Re-probes the folder that owns `file` right before an irreversible decision (trash, `gone`).
    /// A folder that went away since the last refresh (unmount, revoked access) must pause its items,
    /// not lose them: if it is no longer reachable, all statuses are refreshed and `false` is returned.
    func confirmFolderAvailable(for file: TrackedFile) -> Bool {
        guard let id = file.folderId, let folder = folders.first(where: { $0.id == id }) else { return true }
        guard folder.status == .ok else { return false }
        guard probeStatus(of: folder.path) == .ok else {
            refreshFolderStatuses()
            return false
        }
        return true
    }

    /// Notices folders that came back (remount, access granted) without waiting for a wake.
    func reprobeUnavailableFolders() {
        guard folders.contains(where: { $0.status != .ok && probe($0).status == .ok }) else { return }
        refreshFolderStatuses()
    }

    /// The folder's current path (re-resolved through its bookmark when it moved) and status.
    private func probe(_ folder: WatchedFolder) -> (path: String, status: FolderStatus) {
        var path = folder.path
        if env.fs.stat(path)?.isDirectory != true, let bookmark = folder.bookmark,
            let resolved = env.fs.resolveBookmark(bookmark).map(env.fs.canonicalPath),
            resolved != path, env.fs.stat(resolved)?.isDirectory == true
        {
            path = resolved
        }
        return (path, probeStatus(of: path))
    }

    func refreshFolderStatuses() {
        var anyChanged = false
        var recovered: [WatchedFolder] = []
        for var folder in folders {
            let (path, status) = probe(folder)
            var changed = path != folder.path
            folder.path = path
            if status != folder.status {
                if status == .ok {
                    recovered.append(folder)
                } else if folder.status == .ok, let id = folder.id {
                    unavailableSince[id] = env.time.now()
                }
                folder.status = status
                changed = true
            }
            if changed {
                try? store.updateFolder(folder)
                anyChanged = true
            }
        }
        guard anyChanged else { return }
        folders = (try? store.folders()) ?? folders
        notify.yield(.foldersChanged)
        if isRunning { restartWatcher() }
        rescanRecovered(recovered)
    }

    private func probeStatus(of path: String) -> FolderStatus {
        guard env.fs.stat(path)?.isDirectory == true else { return .unavailable }
        do {
            _ = try env.fs.contentsOfDirectory(path)
            return .ok
        } catch FileSystemError.noPermission {
            return .noAccess
        } catch {
            return .unavailable
        }
    }

    /// Items that arrived while a folder was unavailable produced no usable events: scan for them.
    private func rescanRecovered(_ recovered: [WatchedFolder]) {
        let now = env.time.now()
        for old in recovered {
            guard let id = old.id, let folder = folders.first(where: { $0.id == id }) else { continue }
            let since = unavailableSince.removeValue(forKey: id) ?? scanBound ?? folder.addedAt
            scanForNewItems(in: [folder], since: since, now: now)
        }
    }
}
