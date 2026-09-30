import Foundation

extension DropKeeperEngine {
    // MARK: User actions

    public func schedule(ids: [FileID], duration: TimeInterval) throws {
        let now = env.time.now()
        for id in ids {
            guard var file = try store.file(id: id), file.state.isActive else { continue }
            actions.schedule(&file, duration: duration, now: now, tagEnabled: settings.finderTagEnabled)
            try store.update(file)
        }
        rescheduleTimer()
    }

    public func keep(ids: [FileID]) throws {
        let now = env.time.now()
        for id in ids {
            guard var file = try store.file(id: id), file.state.isActive || file.state == .failed else { continue }
            actions.keep(&file, now: now)
            try store.update(file)
        }
        rescheduleTimer()
    }

    /// Moves trashed items back to their original location (a unique name if it is taken); they become `kept`.
    public func undoTrash(ids: [FileID]) throws {
        let now = env.time.now()
        for id in ids {
            guard var file = try store.file(id: id), file.state == .trashed, file.trashPath != nil else { continue }
            try trasher.undo(&file, now: now)
            // The restored file still carries the expiry xattr and Finder tag from before disposal.
            actions.clearMarks(at: file.path)
            if let stat = env.fs.stat(file.path) {
                file.inode = stat.inode
                file.volumeId = stat.volumeId
            }
            file.folderId = folders.first { $0.contains(file.path) }?.id ?? file.folderId
            try store.update(file)
        }
    }

    /// Re-attempts disposal of `failed` items immediately.
    public func retry(ids: [FileID]) throws {
        let now = env.time.now()
        for id in ids {
            guard var file = try store.file(id: id), file.state == .failed else { continue }
            file.state = .scheduled
            file.expiresAt = now
            file.failureCount = 0
            file.updatedAt = now
            try store.update(file)
        }
        runDue()
        rescheduleTimer()
    }

    /// Stops watching a folder. Its active and failed items become `kept`; nothing is trashed.
    public func removeFolder(id: Int64) throws {
        let now = env.time.now()
        for var file in try store.files(in: [.pending, .scheduled, .failed], folderId: id) {
            actions.keep(&file, now: now)
            try store.update(file)
        }
        try store.deleteFolder(id: id)
        unavailableSince[id] = nil
        folders = try store.folders()
        notify.yield(.foldersChanged)
        if isRunning { restartWatcher() }
        rescheduleTimer()
    }

    public func updateSettings(_ new: Settings) throws {
        let normalized = new.normalized()
        if normalized.finderTagEnabled != settings.finderTagEnabled {
            actions.setTag(normalized.finderTagEnabled, for: try store.files(in: [.scheduled]))
        }
        try store.saveSettings(normalized)
        settings = normalized
        rescheduleTimer()
    }

    /// Deletes all history records (kept, trashed, gone, failed); active records stay.
    /// The time is remembered so files that outlive their records are not re-detected (see `orphanBound`).
    public func clearHistory() throws -> Int {
        try store.setMeta(.lastHistoryClearAt, ISODate.format(env.time.now()))
        return try Maintenance(store: store).clearHistory()
    }
}
