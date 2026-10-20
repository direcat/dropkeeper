import Foundation

/// One `deleteNow` disposal attempt did not succeed; `forEach` reports the id.
private enum DeleteNowError: Error {
    case notDisposed
}

extension DropKeeperEngine {
    // MARK: User actions

    /// Schedules active items. Every id is processed; failures are reported together afterwards.
    public func schedule(ids: [FileID], duration: TimeInterval) throws {
        let now = env.time.now()
        defer { rescheduleTimer() }
        try forEach(ids) { id in
            guard var file = try store.file(id: id), file.state.isActive else { return }
            actions.schedule(&file, duration: duration, now: now, tagEnabled: settings.finderTagEnabled)
            try store.update(file)
        }
    }

    /// Keeps active and failed items. Every id is processed; failures are reported together afterwards.
    public func keep(ids: [FileID]) throws {
        let now = env.time.now()
        defer { rescheduleTimer() }
        try forEach(ids) { id in
            guard var file = try store.file(id: id), file.state.isActive || file.state == .failed else { return }
            actions.keep(&file, now: now)
            try store.update(file)
        }
    }

    /// Moves trashed items back to their original location (a unique name if it is taken); they become `kept`.
    /// Every id is processed; the ones that could not be restored are reported in `partialFailure`.
    public func undoTrash(ids: [FileID]) throws {
        let now = env.time.now()
        try forEach(ids) { id in
            guard var file = try store.file(id: id), file.state == .trashed, file.trashPath != nil else { return }
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

    /// Re-attempts disposal of `failed` items immediately. Every id is processed; failures are reported
    /// together afterwards.
    public func retry(ids: [FileID]) throws {
        let now = env.time.now()
        defer {
            runDue()
            rescheduleTimer()
        }
        try forEach(ids) { id in
            guard var file = try store.file(id: id), file.state == .failed else { return }
            file.state = .scheduled
            file.expiresAt = now
            file.failureCount = 0
            file.updatedAt = now
            try store.update(file)
        }
    }

    /// Disposes of active and failed items right away, honouring the delete mode, like an expiry would:
    /// the same notice (with Undo) is emitted. A missing file is recorded as `gone`. A disposal that fails is
    /// not retried and leaves the record untouched. Every id is processed; failures are reported together
    /// afterwards.
    public func deleteNow(ids: [FileID]) throws {
        let now = env.time.now()
        var trashed: [TrackedFile] = []
        defer {
            if !trashed.isEmpty { notify.yield(.trashed(trashed)) }
            rescheduleTimer()
        }
        try forEach(ids) { id in
            guard var file = try store.file(id: id), file.state.isActive || file.state == .failed else { return }
            let outcome = reconciler.reconcile(&file, folders: folders, now: now)
            if outcome == .kept || outcome == .gone {
                persist(file, outcome: outcome)
                return
            }
            guard trasher.dispose(&file, mode: settings.deleteMode, now: now) == .disposed else {
                throw DeleteNowError.notDisposed
            }
            try store.update(file)
            trashed.append(file)
        }
    }

    /// Stops watching a folder. Its active and failed items become `kept`; nothing is trashed.
    /// The folder is removed even when some items could not be updated: once it is not watched, reconciling
    /// such an item finds it outside all watched folders and keeps it. Those ids are reported afterwards.
    public func removeFolder(id: Int64) throws {
        let now = env.time.now()
        var failed: [FileID] = []
        for var file in try store.files(in: [.pending, .scheduled, .failed], folderId: id) {
            actions.keep(&file, now: now)
            do {
                try store.update(file)
            } catch {
                Log.engine.error("Could not keep \(file.id): \(error.localizedDescription)")
                failed.append(file.id)
            }
        }
        try store.deleteFolder(id: id)
        unavailableSince[id] = nil
        folders = try store.folders()
        notify.yield(.foldersChanged)
        if isRunning { restartWatcher() }
        rescheduleTimer()
        if !failed.isEmpty { throw EngineError.partialFailure(failedIds: failed) }
    }

    /// Runs `body` for every id, then throws `partialFailure` listing the ids whose body threw.
    private func forEach(_ ids: [FileID], _ body: (FileID) throws -> Void) throws {
        var failed: [FileID] = []
        for id in ids {
            do {
                try body(id)
            } catch {
                Log.engine.error("Action failed for \(id): \(error.localizedDescription)")
                failed.append(id)
            }
        }
        if !failed.isEmpty { throw EngineError.partialFailure(failedIds: failed) }
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
