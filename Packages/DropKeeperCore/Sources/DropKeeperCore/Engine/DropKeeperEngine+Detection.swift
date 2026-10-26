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
                path: path, folderPath: folder.path, ignoredPatterns: settings.ignoredPatterns)
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
        var applications: [RuleApplication] = []
        for (path, stat) in tracker.poll(now: now, fs: env.fs) {
            guard let folder = folder(containing: path),
                DownloadDetector.isCandidate(
                    path: path, folderPath: folder.path, ignoredPatterns: settings.ignoredPatterns),
                trackedRecord(at: path, stat: stat) == nil
            else { continue }
            // A comparison is still running for this path: poll consumed the entry, so keep it observed. A file
            // that changed meanwhile is picked up again once the check has ended.
            guard duplicateChecks[path] == nil else {
                tracker.observe(path, size: stat.size, now: now)
                continue
            }
            var file = TrackedFile.new(path: path, stat: stat, folderId: folder.id, now: now)
            // Marked at once, also for a rule-matched file whose insert waits for the compare: a Finder copy
            // must not keep the original's id while the original may be gone before the check ends.
            markPending(file)
            let rule = RuleMatcher.firstMatch(
                name: (path as NSString).lastPathComponent, path: path, folderPath: folder.path,
                rules: settings.rules, fs: env.fs)
            let candidates =
                settings.duplicateDetection
                ? DuplicateFinder.candidates(
                    path: path, size: stat.size, folderPath: folder.path,
                    ignoredPatterns: settings.ignoredPatterns, fs: env.fs)
                : []
            if !candidates.isEmpty {
                // Without a rule the prompt appears right away; the duplicate hint follows the check.
                // A rule-matched file is inserted only when the check ends.
                if rule == nil { _ = insert(file) }
                startDuplicateCheck(file: file, stat: stat, rule: rule, candidates: candidates, folder: folder)
                continue
            }
            if let rule {
                // Scheduled before the insert: one write, so the record is never observable as pending.
                actions.schedule(&file, duration: rule.duration, now: now, tagEnabled: settings.finderTagEnabled)
                guard insert(file) else { continue }
                applications.append(RuleApplication(file: file, ruleId: rule.id, ruleName: rule.name))
            } else {
                _ = insert(file)
            }
        }
        if !applications.isEmpty { notify.yield(.ruleApplied(applications)) }
    }

    /// A duplicate may carry the original's expiry xattr and tag; markPending overwrites the id.
    private func markPending(_ file: TrackedFile) {
        actions.clearMarks(at: file.path)
        actions.markPending(file)
    }

    // MARK: Duplicate check

    /// Compares the new file's bytes with the same-size candidates off the actor, then hops back to finish.
    /// A rule-matched file is not inserted until the check ends, so it is never observable as pending.
    private func startDuplicateCheck(
        file: TrackedFile, stat: FileStat, rule: Rule?, candidates: [String], folder: WatchedFolder
    ) {
        let fs = env.fs
        let path = file.path
        let folderPath = folder.path
        let task = Task.detached(priority: .utility) { [weak self] in
            let name = DuplicateFinder.firstMatch(path: path, candidates: candidates, folderPath: folderPath, fs: fs)
            await self?.finishDuplicateCheck(file: file, stat: stat, rule: rule, duplicate: name)
        }
        duplicateChecks[path] = DuplicateCheck(task: task, file: file, awaitsInsert: rule != nil)
    }

    func finishDuplicateCheck(file: TrackedFile, stat: FileStat, rule: Rule?, duplicate: String?) {
        duplicateChecks[file.path] = nil
        guard isRunning else { return }
        // Settings may have changed during the comparison.
        let duplicate = settings.duplicateDetection ? duplicate : nil
        guard rule != nil else {
            // Only a record that is still the same pending item gets the hint.
            guard let name = duplicate, var current = try? store.file(id: file.id), current.state == .pending,
                current.path == file.path
            else { return }
            current.duplicateOf = name
            update(current)
            return
        }
        let now = env.time.now()
        guard let folder = validatedFolder(for: file, stat: stat, now: now) else { return }
        // The rule may have been disabled or removed meanwhile: then the file is a plain pending item.
        let current = RuleMatcher.firstMatch(
            name: (file.path as NSString).lastPathComponent, path: file.path, folderPath: folder.path,
            rules: settings.rules, fs: env.fs)
        var file = file
        if let duplicate {
            // The duplicate stays pending for the user to decide; the rule's duration applies after the grace period.
            file.duplicateOf = duplicate
            file.scheduleDuration = current?.duration
        } else if let current {
            actions.schedule(&file, duration: current.duration, now: now, tagEnabled: settings.finderTagEnabled)
        }
        guard insert(file) else { return }
        if file.state == .scheduled, let current {
            notify.yield(.ruleApplied([RuleApplication(file: file, ruleId: current.id, ruleName: current.name)]))
        }
    }

    /// The folder to insert a rule-path file into, or nil when the file vanished, changed, was claimed or its
    /// folder is gone. A changed file is observed again; the marks of a file that is still ours are cleared.
    private func validatedFolder(for file: TrackedFile, stat: FileStat, now: Date) -> WatchedFolder? {
        // The file may have vanished or changed while the bytes were compared; normal detection sees it again.
        guard let fresh = env.fs.stat(file.path) else { return nil }
        let isSameFile = fresh.inode == stat.inode && fresh.volumeId == stat.volumeId
        guard isSameFile, fresh.size == stat.size else {
            // A replaced file is not ours to clear; the same file that grew still carries our marks.
            if isSameFile { actions.clearMarks(at: file.path) }
            tracker.observe(file.path, size: fresh.size, now: now)
            return nil
        }
        guard let folder = folder(containing: file.path) else {
            actions.clearMarks(at: file.path)
            return nil
        }
        return trackedRecord(at: file.path, stat: fresh) == nil ? folder : nil
    }

    /// Waits for every running duplicate check to finish (tests only).
    func awaitDuplicateChecks() async {
        while let check = duplicateChecks.values.first { await check.task.value }
    }

    /// Lets running checks finish normally before shutdown; after `timeout` the files still waiting for their
    /// check become plain pending records (no rule applied), so the next launch prompts for them.
    func drainDuplicateChecks(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while !duplicateChecks.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        for check in duplicateChecks.values where check.awaitsInsert {
            let file = check.file
            guard let stat = env.fs.stat(file.path), stat.inode == file.inode, stat.volumeId == file.volumeId,
                folder(containing: file.path) != nil, trackedRecord(at: file.path, stat: stat) == nil
            else { continue }
            _ = insert(file)
        }
        duplicateChecks = [:]
    }

    private func insert(_ file: TrackedFile) -> Bool {
        do {
            try store.insert(file)
            return true
        } catch {
            Log.engine.error("Could not insert record: \(error.localizedDescription)")
            return false
        }
    }

    private func update(_ file: TrackedFile) {
        do {
            try store.update(file)
        } catch {
            Log.engine.error("Could not update record: \(error.localizedDescription)")
        }
    }
}
