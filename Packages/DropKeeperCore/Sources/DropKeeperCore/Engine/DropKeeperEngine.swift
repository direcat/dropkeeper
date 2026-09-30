import Foundation
import GRDB

public struct EngineEnvironment: Sendable {
    public var store: FileStore
    public var fs: any FileSystem
    public var time: any TimeSource
    public var makeEventSource: @Sendable ([String], UInt64?) throws -> any FolderEventSource
    public var currentEventId: @Sendable () -> UInt64
    public var needsRecovery: Bool
    public var recoveryFolderHints: [String]
    public var automaticTimer: Bool

    public init(
        store: FileStore, fs: any FileSystem, time: any TimeSource,
        makeEventSource: @escaping @Sendable ([String], UInt64?) throws -> any FolderEventSource,
        currentEventId: @escaping @Sendable () -> UInt64, needsRecovery: Bool, recoveryFolderHints: [String],
        automaticTimer: Bool
    ) {
        self.store = store
        self.fs = fs
        self.time = time
        self.makeEventSource = makeEventSource
        self.currentEventId = currentEventId
        self.needsRecovery = needsRecovery
        self.recoveryFolderHints = recoveryFolderHints
        self.automaticTimer = automaticTimer
    }

    public static func live(store: FileStore, needsRecovery: Bool, recoveryFolderHints: [String]) -> EngineEnvironment {
        EngineEnvironment(
            store: store, fs: LiveFileSystem(), time: SystemTimeSource(),
            makeEventSource: { paths, since in try FolderWatcher(paths: paths, since: since) },
            currentEventId: { FolderWatcher.currentEventId() },
            needsRecovery: needsRecovery, recoveryFolderHints: recoveryFolderHints, automaticTimer: true)
    }
}

public enum EngineNotification: Sendable, Equatable {
    case trashed([TrackedFile])
    case failed(TrackedFile)
    case foldersChanged
}

public enum EngineError: Error, Equatable {
    case notADirectory(String)
    case overlapsExistingFolder(String)
}

public actor DropKeeperEngine {
    public static let heartbeatInterval: TimeInterval = 300
    public static let maintenanceInterval: TimeInterval = 86_400
    public static let pollInterval: TimeInterval = 0.5

    public nonisolated let notifications: AsyncStream<EngineNotification>
    private let notify: AsyncStream<EngineNotification>.Continuation
    private let env: EngineEnvironment
    private var settings = Settings()
    private var folders: [WatchedFolder] = []
    private var tracker = StabilityTracker()
    private var eventSource: (any FolderEventSource)?
    private var eventTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var isRunning = false
    /// Lower bound for the fallback scan: the heartbeat from the previous session.
    private var scanBound: Date?
    /// When each folder (by id) stopped being `.ok` during this session; bounds its rescan on return.
    private var unavailableSince: [Int64: Date] = [:]

    private var store: FileStore { env.store }
    private var actions: ItemActions { ItemActions(fs: env.fs) }
    private var reconciler: Reconciler { Reconciler(fs: env.fs) }
    private var trasher: Trasher { Trasher(fs: env.fs) }

    public init(environment: EngineEnvironment) {
        env = environment
        let (stream, continuation) = AsyncStream.makeStream(of: EngineNotification.self)
        notifications = stream
        notify = continuation
    }

    public var currentSettings: Settings { settings }
    public var watchedFolders: [WatchedFolder] { folders }

    public nonisolated func observeFiles(in states: [FileState]) -> AsyncValueObservation<[TrackedFile]> {
        env.store.observeFiles(in: states)
    }

    // MARK: Lifecycle

    public func start() throws {
        guard !isRunning else { return }
        settings = try store.settings()
        folders = try store.folders()
        scanBound = try store.meta(.lastHeartbeatAt).flatMap(ISODate.parse)
        if env.needsRecovery { try recover() }
        if try store.meta(.lastEventId) == nil, !folders.isEmpty {
            try store.setMeta(.lastEventId, String(env.currentEventId()))
        }
        refreshFolderStatuses()
        reconcileActive()
        runDue()
        runMaintenanceIfDue()
        writeHeartbeat()
        isRunning = true
        restartWatcher()
        rescheduleTimer()
    }

    public func stop() {
        writeHeartbeat()
        isRunning = false
        eventTask?.cancel()
        eventSource?.stop()
        eventSource = nil
        timerTask?.cancel()
        timerTask = nil
    }

    public func handleWake() {
        refreshFolderStatuses()
        reconcileActive()
        runDue()
        rescheduleTimer()
    }

    public func handleClockChange() {
        runDue()
        rescheduleTimer()
    }

    // MARK: Folders

    public func addFolder(path: String) throws -> WatchedFolder {
        let canonical = env.fs.canonicalPath(path)
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

    private func insertFolder(path: String) throws -> WatchedFolder {
        let folder = WatchedFolder(
            id: nil, path: path, bookmark: env.fs.bookmark(for: path), volumeId: env.fs.stat(path)?.volumeId ?? "",
            addedAt: env.time.now(), baselineEventId: env.currentEventId(), status: .ok)
        let inserted = try store.insertFolder(folder)
        folders = try store.folders()
        return inserted
    }

    private func folder(containing path: String) -> WatchedFolder? {
        folders.first { $0.status == .ok && $0.contains(path) }
    }

    private func isFolderAvailable(_ id: Int64?) -> Bool {
        guard let id else { return true }
        return folders.first { $0.id == id }?.status == .ok
    }

    private func refreshFolderStatuses() {
        var anyChanged = false
        var recovered: [WatchedFolder] = []
        for var folder in folders {
            var changed = false
            if env.fs.stat(folder.path)?.isDirectory != true, let bookmark = folder.bookmark,
                let resolved = env.fs.resolveBookmark(bookmark).map(env.fs.canonicalPath),
                resolved != folder.path, env.fs.stat(resolved)?.isDirectory == true
            {
                folder.path = resolved
                changed = true
            }
            let status = probeStatus(of: folder.path)
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

    // MARK: Watcher

    private func restartWatcher() {
        eventTask?.cancel()
        eventSource?.stop()
        eventSource = nil
        let paths = folders.filter { $0.status == .ok }.map(\.path)
        guard !paths.isEmpty else { return }
        let since = (try? store.meta(.lastEventId)).flatMap { UInt64($0) }
        do {
            let source = try env.makeEventSource(paths, since)
            eventSource = source
            eventTask = Task { [weak self] in
                for await batch in source.events {
                    await self?.handle(events: batch)
                }
            }
        } catch {
            Log.watcher.error("Could not start watcher: \(error.localizedDescription)")
        }
    }

    func handle(events: [FolderEvent]) {
        guard isRunning else { return }
        let now = env.time.now()
        var needsRescan = false
        var maxId: UInt64 = 0
        for event in events {
            maxId = max(maxId, event.id)
            if event.flags.contains(.mustScanSubDirs) || event.flags.contains(.idsWrapped) {
                needsRescan = true
                continue
            }
            if event.flags.contains(.rootChanged) {
                refreshFolderStatuses()
                continue
            }
            guard let folder = folder(containing: event.path) else { continue }
            if event.id != 0, event.id <= folder.baselineEventId { continue }
            process(path: event.path, flags: event.flags, folder: folder, now: now)
        }
        if maxId > 0 {
            let stored = (try? store.meta(.lastEventId)).flatMap { UInt64($0) } ?? 0
            if maxId > stored { try? store.setMeta(.lastEventId, String(maxId)) }
        }
        if needsRescan {
            scanForNewItems(in: folders.filter { $0.status == .ok }, since: scanBound ?? now, now: now)
        }
        pollTracker(now: now)
        runDue()
        rescheduleTimer()
    }

    private func process(path: String, flags: FolderEventFlags, folder: WatchedFolder, now: Date) {
        guard let stat = env.fs.stat(path) else {
            for var file in (try? store.files(in: [.pending, .scheduled], path: path)) ?? [] {
                let outcome = reconciler.reconcile(&file, folders: folders, now: now)
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
        guard isNewItem(path: path, stat: stat, folder: folder, since: folder.addedAt) else { return }
        tracker.observe(path, size: stat.size, now: now)
    }

    private func isNewItem(path: String, stat: FileStat, folder: WatchedFolder, since: Date) -> Bool {
        guard
            DownloadDetector.isCandidate(
                path: path, folderPath: folder.path, ignoredExtensions: settings.ignoredExtensions)
        else { return false }
        guard let added = stat.addedDate ?? stat.creationDate else { return false }
        return added >= since
    }

    /// Identity per spec §3.1: inode + volume first, the id xattr only as a fallback.
    /// A path carrying the id of a record whose original is still in place is a duplicate
    /// (e.g. a Finder copy) and is treated as a new item.
    private func trackedRecord(at path: String, stat: FileStat) -> TrackedFile? {
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

    private func persist(_ file: TrackedFile, outcome: ReconcileOutcome) {
        guard outcome != .unchanged else { return }
        if file.state == .kept { actions.clearMarks(at: file.path) }
        do {
            try store.update(file)
        } catch {
            Log.engine.error("Could not persist \(file.id): \(error.localizedDescription)")
        }
    }

    private func scanForNewItems(in scanned: [WatchedFolder], since bound: Date, now: Date) {
        for folder in scanned where folder.status == .ok {
            let since = max(bound, folder.addedAt)
            for name in (try? env.fs.contentsOfDirectory(folder.path)) ?? [] {
                let path = folder.path + "/" + name
                guard let stat = env.fs.stat(path), trackedRecord(at: path, stat: stat) == nil,
                    isNewItem(path: path, stat: stat, folder: folder, since: since)
                else { continue }
                tracker.observe(path, size: stat.size, now: now)
            }
        }
    }

    private func pollTracker(now: Date) {
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

    // MARK: Scheduling

    func tick() {
        guard isRunning else { return }
        let now = env.time.now()
        pollTracker(now: now)
        runDue()
        writeHeartbeat()
        runMaintenanceIfDue()
        rescheduleTimer()
    }

    private func reconcileActive() {
        let now = env.time.now()
        for var file in (try? store.files(in: [.pending, .scheduled])) ?? [] where isFolderAvailable(file.folderId) {
            let outcome = reconciler.reconcile(&file, folders: folders, now: now)
            persist(file, outcome: outcome)
        }
    }

    private func runDue() {
        let now = env.time.now()
        guard let active = try? store.files(in: [.pending, .scheduled]) else { return }
        var trashed: [TrackedFile] = []
        for var file in active {
            guard let deadline = Scheduler.deadline(for: file, settings: settings), deadline <= now,
                isFolderAvailable(file.folderId)
            else { continue }
            let outcome = reconciler.reconcile(&file, folders: folders, now: now)
            if outcome == .kept || outcome == .gone {
                persist(file, outcome: outcome)
                continue
            }
            switch file.state {
            case .pending:
                applyDefaultChoice(&file, now: now)
            case .scheduled:
                dispose(&file, now: now, trashed: &trashed)
            case .kept, .trashed, .gone, .failed:
                break
            }
            do {
                try store.update(file)
            } catch {
                Log.engine.error("Could not persist \(file.id): \(error.localizedDescription)")
            }
        }
        if !trashed.isEmpty { notify.yield(.trashed(trashed)) }
    }

    /// One disposal attempt for an expired scheduled record; collects successes into `trashed`.
    private func dispose(_ file: inout TrackedFile, now: Date, trashed: inout [TrackedFile]) {
        switch trasher.dispose(&file, mode: settings.deleteMode, now: now) {
        case .disposed: trashed.append(file)
        case .failed: notify.yield(.failed(file))
        case .retryScheduled: break
        }
    }

    private func applyDefaultChoice(_ file: inout TrackedFile, now: Date) {
        switch settings.defaultChoice {
        case .keep:
            actions.keep(&file, now: now)
        case .expireAfter(let duration):
            actions.schedule(&file, duration: duration, now: now, tagEnabled: settings.finderTagEnabled)
        }
    }

    private func rescheduleTimer() {
        timerTask?.cancel()
        timerTask = nil
        guard env.automaticTimer, isRunning else { return }
        let now = env.time.now()
        var wake = now.addingTimeInterval(Self.heartbeatInterval)
        let active = ((try? store.files(in: [.pending, .scheduled])) ?? []).filter { isFolderAvailable($0.folderId) }
        if let deadline = Scheduler.nextDeadline(in: active, settings: settings) { wake = min(wake, deadline) }
        if !tracker.isEmpty { wake = min(wake, now.addingTimeInterval(Self.pollInterval)) }
        if let last = metaDate(.lastMaintenanceAt) {
            wake = min(wake, last.addingTimeInterval(Self.maintenanceInterval))
        }
        let delay = max(0.25, wake.timeIntervalSince(now))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

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
}

extension DropKeeperEngine {
    // MARK: Housekeeping

    private func metaDate(_ key: MetaKey) -> Date? {
        (try? store.meta(key)).flatMap(ISODate.parse)
    }

    private func writeHeartbeat() {
        try? store.setMeta(.lastHeartbeatAt, ISODate.format(env.time.now()))
    }

    private func runMaintenanceIfDue() {
        let now = env.time.now()
        if let last = metaDate(.lastMaintenanceAt), now.timeIntervalSince(last) < Self.maintenanceInterval { return }
        do {
            let deleted = try Maintenance(store: store).run(retention: settings.historyRetention, now: now)
            Log.store.info("Maintenance removed \(deleted) records")
        } catch {
            Log.store.error("Maintenance failed: \(error.localizedDescription)")
        }
        try? store.setMeta(.lastMaintenanceAt, ISODate.format(now))
    }

    private func recover() throws {
        for hint in env.recoveryFolderHints {
            let path = env.fs.canonicalPath(hint)
            guard !folders.contains(where: { $0.path == path }), env.fs.stat(path)?.isDirectory == true else {
                continue
            }
            _ = try insertFolder(path: path)
        }
        let now = env.time.now()
        for file in Recovery(fs: env.fs).scan(folders: folders, now: now) where (try? store.file(id: file.id)) == nil {
            try store.insert(file)
        }
    }
}

extension WatchedFolder {
    /// True when `child` lies inside `parent`.
    static func contains(parent: String, _ child: String) -> Bool {
        child.hasPrefix(parent + "/")
    }
}
