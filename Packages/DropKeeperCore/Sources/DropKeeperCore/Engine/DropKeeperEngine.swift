import Foundation
import GRDB

public struct EngineEnvironment: Sendable {
    public var store: FileStore
    public var fs: any FileSystem
    public var time: any TimeSource
    public var makeEventSource: @Sendable ([String], UInt64?) throws -> any FolderEventSource
    public var currentEventId: @Sendable () -> UInt64
    /// True only when the database was lost or corrupt (e.g. `StoreOpenResult.recoveredFromCorruption`,
    /// or a new database while the app knows it ran before). Must be false on a genuine first launch,
    /// where existing folder contents are never recorded.
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
    case ruleApplied([RuleApplication])
}

public enum EngineError: Error, Equatable {
    case notADirectory(String)
    /// The path cannot be watched (e.g. the filesystem root).
    case invalidFolder(String)
    case overlapsExistingFolder(String)
    /// A batch action processed every item but these failed.
    case partialFailure(failedIds: [FileID])
}

public actor DropKeeperEngine {
    public static let heartbeatInterval: TimeInterval = 300
    public static let maintenanceInterval: TimeInterval = 86_400
    public static let pollInterval: TimeInterval = 0.5

    /// Engine events for the UI. Single consumer: `AsyncStream` delivers each element to one iterator only,
    /// so the app must iterate it from exactly one place and fan out from there.
    public nonisolated let notifications: AsyncStream<EngineNotification>
    let notify: AsyncStream<EngineNotification>.Continuation
    let env: EngineEnvironment
    var settings = Settings()
    var folders: [WatchedFolder] = []
    var tracker = StabilityTracker()
    private var eventSource: (any FolderEventSource)?
    private var eventTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    var isRunning = false
    /// Lower bound for the fallback scan: the heartbeat from the previous session.
    var scanBound: Date?
    /// When each folder (by id) stopped being `.ok` during this session; bounds its rescan on return.
    var unavailableSince: [Int64: Date] = [:]
    /// Off-actor duplicate comparisons in flight, by path; also keeps a file from being detected twice meanwhile.
    var duplicateChecks: [String: DuplicateCheck] = [:]

    struct DuplicateCheck {
        let task: Task<Void, Never>
        let file: TrackedFile
        /// A rule-matched file has no record until its check ends.
        let awaitsInsert: Bool
    }

    var store: FileStore { env.store }
    var actions: ItemActions { ItemActions(fs: env.fs) }
    var reconciler: Reconciler { Reconciler(fs: env.fs) }
    var trasher: Trasher { Trasher(fs: env.fs) }

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

    /// `observeFiles(in:)` as a standard-library stream, for clients that do not link GRDB themselves
    /// (the app target: GRDB is linked into this package's framework and its generic symbols are not exported).
    /// Only the newest value is buffered. The observation runs until the stream is iterated to its end, or its
    /// iterating task is cancelled, or the stream is dropped — iterate it or drop it to stop the observation.
    public nonisolated func fileUpdates(in states: [FileState]) -> AsyncThrowingStream<[TrackedFile], any Error> {
        let observation = observeFiles(in: states)
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    for try await files in observation {
                        continuation.yield(files)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
        // Downloads still stabilizing at quit (or missed by the replay) are found by the fallback scan,
        // bounded by the previous heartbeat. Without a previous heartbeat nothing is admitted.
        if let scanBound {
            scanForNewItems(in: folders.filter { $0.status == .ok }, since: scanBound, now: env.time.now())
        }
        reconcileActive()
        runDue()
        runMaintenanceIfDue()
        writeHeartbeat()
        isRunning = true
        restartWatcher()
        rescheduleTimer()
    }

    /// Stops the engine. Running duplicate checks finish first (bounded by `drainTimeout`), so a file whose
    /// rule outcome is still pending is not lost.
    public func stop(drainTimeout: Duration = .seconds(2)) async {
        if isRunning { await drainDuplicateChecks(timeout: drainTimeout) }
        writeHeartbeat()
        isRunning = false
        eventTask?.cancel()
        eventSource?.stop()
        eventSource = nil
        timerTask?.cancel()
        timerTask = nil
    }

    public func handleWake() {
        refreshFolders()
    }

    /// Re-checks every watched folder now (e.g. after the user granted access in System Settings):
    /// statuses are refreshed, folders that came back are rescanned, and overdue items are processed.
    public func refreshFolders() {
        guard isRunning else { return }
        refreshFolderStatuses()
        reconcileActive()
        runDue()
        rescheduleTimer()
    }

    public func handleClockChange() {
        guard isRunning else { return }
        runDue()
        rescheduleTimer()
    }

    // MARK: Watcher

    func restartWatcher() {
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

    // MARK: Scheduling

    func tick() {
        guard isRunning else { return }
        reprobeUnavailableFolders()
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
            if outcome == .gone, !confirmFolderAvailable(for: file) { continue }
            persist(file, outcome: outcome)
        }
    }

    func runDue() {
        let now = env.time.now()
        guard let active = try? store.files(in: [.pending, .scheduled]) else { return }
        var trashed: [TrackedFile] = []
        var confirmedFolders: Set<Int64> = []
        for var file in active where isDue(file, now: now, confirmedFolders: &confirmedFolders) {
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

    /// True when `file`'s deadline passed and its folder is reachable. Each owning folder is re-probed once
    /// per pass: a lost folder pauses its items instead of letting them be reconciled as gone (unmount) or
    /// trashed while access is revoked.
    private func isDue(_ file: TrackedFile, now: Date, confirmedFolders: inout Set<Int64>) -> Bool {
        guard let deadline = Scheduler.deadline(for: file, settings: settings), deadline <= now,
            isFolderAvailable(file.folderId)
        else { return false }
        guard let folderId = file.folderId, !confirmedFolders.contains(folderId) else { return true }
        guard confirmFolderAvailable(for: file) else { return false }
        confirmedFolders.insert(folderId)
        return true
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
        // A duplicate that matched a rule kept the rule's duration while it waited for the user.
        if let duration = file.scheduleDuration {
            actions.schedule(&file, duration: duration, now: now, tagEnabled: settings.finderTagEnabled)
            return
        }
        switch settings.resolve(lastChoice: storedLastChoice()) {
        case .keep:
            actions.keep(&file, now: now)
        case .expireAfter(let duration):
            actions.schedule(&file, duration: duration, now: now, tagEnabled: settings.finderTagEnabled)
        }
    }

    func rescheduleTimer() {
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
}

extension DropKeeperEngine {
    // MARK: Housekeeping

    /// The action the default currently resolves to (reads the remembered choice and the settings).
    public var resolvedDefaultChoice: ResolvedChoice { settings.resolve(lastChoice: storedLastChoice()) }

    func storedLastChoice() -> ResolvedChoice? {
        guard let raw = (try? store.meta(.lastChoice)) ?? nil else { return nil }
        if raw == "keep" { return .keep }
        return TimeInterval(raw).map { .expireAfter($0) }
    }

    func storeLastChoice(_ choice: ResolvedChoice) {
        let raw: String
        switch choice {
        case .keep: raw = "keep"
        case .expireAfter(let duration): raw = String(Int64(duration))
        }
        try? store.setMeta(.lastChoice, raw)
    }

    func metaDate(_ key: MetaKey) -> Date? {
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
            // Duplicated ids were reissued by Recovery; kept items must not keep an expiry mark.
            actions.markPending(file)
            if file.state == .kept { actions.clearMarks(at: file.path) }
        }
    }
}

extension WatchedFolder {
    /// True when `child` lies inside `parent`.
    static func contains(parent: String, _ child: String) -> Bool {
        child.hasPrefix(parent + "/")
    }
}
