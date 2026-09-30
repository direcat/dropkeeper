import Foundation

extension DropKeeperEngine {
    // MARK: Detection

    func process(path: String, flags: FolderEventFlags, folder: WatchedFolder, now: Date) {
        guard let stat = env.fs.stat(path) else {
            for var file in (try? store.files(in: [.pending, .scheduled], path: path)) ?? [] {
                let outcome = reconciler.reconcile(&file, folders: folders, now: now)
                if outcome == .gone, !confirmFolderAvailable(for: file) { continue }
                persist(file, outcome: outcome)
            }
            return
        }
        if var file = trackedRecord(at: path, stat: stat) {
            let outcome = reconciler.adopt(path: path, stat: stat, file: &file, folders: folders, now: now)
            persist(file, outcome: outcome)
            return
        }
        guard flags.contains(.created) || flags.contains(.renamed) else { return }
        guard isNewItem(path: path, stat: stat, folder: folder, since: folder.addedAt, now: now) else { return }
        tracker.observe(path, size: stat.size, now: now)
    }

    /// An untracked path is a new item when it is an eligible direct child added at/after `since`.
    ///
    /// A path carrying a DropKeeper id xattr without any matching record was seen before: its record was
    /// purged (Clear history, retention) while the file stayed. It is new only when it was added
    /// recently, i.e. at/after `orphanBound(now:)`, which admits fresh Finder copies but not renames or
    /// rescans of an item the user already decided on.
    func isNewItem(path: String, stat: FileStat, folder: WatchedFolder, since: Date, now: Date) -> Bool {
        guard
            DownloadDetector.isCandidate(
                path: path, folderPath: folder.path, ignoredExtensions: settings.ignoredExtensions)
        else { return false }
        guard let added = stat.addedDate ?? stat.creationDate else { return false }
        var bound = since
        if let id = env.fs.readXattr(ItemActions.idAttribute, at: path), (try? store.file(id: id)) == nil {
            bound = max(bound, orphanBound(now: now))
        }
        return added >= bound
    }

    /// Lower bound on the added date of a genuinely new item that carries an orphaned id xattr.
    ///
    /// The latest of: the previous session's heartbeat, the last Clear history, and `now − gracePeriod`.
    /// Every record deleted by Clear history or retention belongs to a file added before that bound, so a
    /// rename or rescan never revives it. Residual risk (documented): an orphan moved back into a watched
    /// folder from elsewhere gets a fresh added date and is prompted again as a new item.
    func orphanBound(now: Date) -> Date {
        var bound = now.addingTimeInterval(-settings.gracePeriod)
        if let scanBound { bound = max(bound, scanBound) }
        if let cleared = metaDate(.lastHistoryClearAt) { bound = max(bound, cleared) }
        return bound
    }

    /// Identity per spec §3.1: inode + volume first, the id xattr only as a fallback.
    /// A path carrying the id of a record whose original is still in place is a duplicate
    /// (e.g. a Finder copy) and is treated as a new item.
    func trackedRecord(at path: String, stat: FileStat) -> TrackedFile? {
        if let file = try? store.file(inode: stat.inode, volumeId: stat.volumeId, excluding: [.gone, .trashed]) {
            return file
        }
        guard let id = env.fs.readXattr(ItemActions.idAttribute, at: path), let file = try? store.file(id: id)
        else { return nil }
        if file.path != path, let original = env.fs.stat(file.path), original.inode == file.inode,
            original.volumeId == file.volumeId
        {
            return nil
        }
        return file
    }

    func persist(_ file: TrackedFile, outcome: ReconcileOutcome) {
        guard outcome != .unchanged else { return }
        if file.state == .kept { actions.clearMarks(at: file.path) }
        do {
            try store.update(file)
        } catch {
            Log.engine.error("Could not persist \(file.id): \(error.localizedDescription)")
        }
    }

    func scanForNewItems(in scanned: [WatchedFolder], since bound: Date, now: Date) {
        for folder in scanned where folder.status == .ok {
            let since = max(bound, folder.addedAt)
            for name in (try? env.fs.contentsOfDirectory(folder.path)) ?? [] {
                let path = folder.path + "/" + name
                guard let stat = env.fs.stat(path), trackedRecord(at: path, stat: stat) == nil,
                    isNewItem(path: path, stat: stat, folder: folder, since: since, now: now)
                else { continue }
                tracker.observe(path, size: stat.size, now: now)
            }
        }
    }

    func pollTracker(now: Date) {
        guard !tracker.isEmpty else { return }
        for (path, stat) in tracker.poll(now: now, fs: env.fs) {
            guard let folder = folder(containing: path),
                DownloadDetector.isCandidate(
                    path: path, folderPath: folder.path, ignoredExtensions: settings.ignoredExtensions),
                trackedRecord(at: path, stat: stat) == nil
            else { continue }
            let file = TrackedFile.new(path: path, stat: stat, folderId: folder.id, now: now)
            // A duplicate may carry the original's expiry xattr and tag; markPending overwrites the id.
            actions.clearMarks(at: path)
            actions.markPending(file)
            do {
                try store.insert(file)
            } catch {
                Log.engine.error("Could not insert record: \(error.localizedDescription)")
            }
        }
    }
}
