import DropKeeperCore
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppModel {
    private(set) var pending: [TrackedFile] = []
    private(set) var scheduled: [TrackedFile] = []
    private(set) var failed: [TrackedFile] = []
    private(set) var settings = Settings()
    private(set) var folders: [WatchedFolder] = []
    private(set) var queue = PromptQueue()
    private(set) var notice = NoticeCoalescer()
    private(set) var reminders = ReminderTracker()
    private(set) var now = Date()
    private(set) var lastError: String?
    private(set) var panelError = PanelError()
    private(set) var needsOnboarding = false
    /// What the grace period would apply now; the prompt preselects it.
    private(set) var resolvedChoice = ResolvedChoice.keep
    var timeline = TimelineModel(durations: Settings().timelineStops, preselect: .keep)
    var applyToAll = false
    /// Set when the user asks to review pending files (e.g. from the list) while Quiet mode is on.
    var promptRequested = false

    @ObservationIgnored private var engine: DropKeeperEngine?
    /// Only a started engine is stopped: stopping writes a heartbeat, which would narrow the next launch's scan.
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var panelErrorTask: Task<Void, Never>?
    /// Whether the prompt was shown at the last check, to notice it closing (see `promptVisibilityChanged`).
    @ObservationIgnored private var promptWasAvailable = false
    @ObservationIgnored private var isDeciding = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let applyLoginItem: @MainActor (Bool) -> Void
    @ObservationIgnored private let log = Logger(subsystem: "net.direcat.dropkeeper", category: "app")

    static let onboardingCompletedKey = "onboardingCompleted"
    static let loginItemInitializedKey = "loginItemInitialized"

    /// `applyLoginItem` is injectable so tests never register the test host as a login item.
    init(defaults: UserDefaults = .standard, applyLoginItem: @escaping @MainActor (Bool) -> Void = LoginItem.apply) {
        self.defaults = defaults
        self.applyLoginItem = applyLoginItem
    }

    var urgentSeconds: Int? { Countdown.urgentSeconds(scheduled: scheduled, now: now) }
    var hasProblems: Bool { !failed.isEmpty || folders.contains { $0.status != .ok } }
    var isPromptAvailable: Bool { queue.current != nil && (!settings.quietMode || promptRequested) }

    // MARK: Lifecycle

    @discardableResult
    func start(with bootstrap: EngineBootstrap.Result) async -> Bool {
        engine = bootstrap.engine
        do {
            try await bootstrap.engine.start()
        } catch {
            report(error)
            return false
        }
        isStarted = true
        await refreshState()
        resetPromptState()
        promptVisibilityChanged()
        needsOnboarding =
            bootstrap.isFirstLaunch || (folders.isEmpty && !defaults.bool(forKey: Self.onboardingCompletedKey))
        observeFiles(bootstrap.engine)
        observeNotifications(bootstrap.engine)
        // Only once: later launches must not undo a change the user made in System Settings.
        if !defaults.bool(forKey: Self.loginItemInitializedKey) {
            applyLoginItem(settings.launchAtLogin)
            defaults.set(true, forKey: Self.loginItemInitializedKey)
        }
        return true
    }

    func stop() async {
        for task in tasks { task.cancel() }
        tasks = []
        clockTask?.cancel()
        noticeTask?.cancel()
        panelErrorTask?.cancel()
        guard isStarted else { return }
        isStarted = false
        await engine?.stop()
    }

    func handleWake() async { await engine?.handleWake() }
    func handleClockChange() async { await engine?.handleClockChange() }

    func refreshFolders() async {
        await engine?.refreshFolders()
        await refreshState()
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingCompletedKey)
        needsOnboarding = false
    }

    func clearError() { lastError = nil }

    // MARK: Engine state

    private func observeFiles(_ engine: DropKeeperEngine) {
        let updates = engine.fileUpdates(in: [.pending, .scheduled, .failed])
        tasks.append(
            Task { [weak self] in
                do {
                    for try await files in updates {
                        self?.apply(files)
                    }
                } catch {
                    self?.report(error)
                }
            })
    }

    private func observeNotifications(_ engine: DropKeeperEngine) {
        let stream = engine.notifications
        tasks.append(
            Task { [weak self] in
                for await note in stream {
                    await self?.handle(note)
                }
            })
    }

    func apply(_ files: [TrackedFile]) {
        let previous = queue.current?.id
        pending = files.filter { $0.state == .pending }
        scheduled = files.filter { $0.state == .scheduled }
        failed = files.filter { $0.state == .failed }
        queue.update(pending: pending)
        if queue.current?.id != previous { resetPromptState() }
        if queue.current == nil { promptRequested = false }
        promptVisibilityChanged()
        scheduleClock()
    }

    func handle(_ note: EngineNotification) async {
        switch note {
        case .trashed(let files):
            notice.add(files, now: Date())
            scheduleNoticeExpiry()
        case .failed:
            break  // failed files arrive through the file observation
        case .foldersChanged:
            await refreshState()
        case .ruleApplied:
            break  // the notice for applied rules comes with the 1.1 UI
        }
    }

    private func refreshState() async {
        guard let engine else { return }
        settings = await engine.currentSettings
        folders = await engine.watchedFolders
        resolvedChoice = await engine.resolvedDefaultChoice
        EngineBootstrap.rememberFolders(folders, defaults: defaults)
    }

    private func resetPromptState() {
        timeline = TimelineModel(durations: settings.timelineStops, preselect: resolvedChoice)
        applyToAll = false
    }

    private func scheduleClock() {
        clockTask?.cancel()
        now = Date()
        // Reminders become due by time passing, so they are refreshed on every tick and their wake is merged in
        // before the early return: with no file near expiry the clock must still fire when a window opens.
        reminders.update(
            scheduled: scheduled, now: now, enabled: settings.reminderEnabled, leadTime: settings.reminderLeadTime)
        let reminderWake = reminders.nextWake(
            scheduled: scheduled, now: now, enabled: settings.reminderEnabled, leadTime: settings.reminderLeadTime)
        let countdownWake = Countdown.nextRefresh(scheduled: scheduled, now: now)
        guard let next = [countdownWake, reminderWake].compactMap(\.self).min() else { return }
        let delay = max(0.1, next.timeIntervalSince(now))
        clockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scheduleClock()
        }
    }

    /// A notice that runs out while the prompt is shown is held; `promptVisibilityChanged` shows it afterwards.
    private func scheduleNoticeExpiry() {
        noticeTask?.cancel()
        guard let expiresAt = notice.expiresAt else { return }
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.notice.expireIfDue(now: Date(), promptShown: self.isPromptAvailable)
        }
    }

    /// Call after anything that can open or close the prompt. When it closed, a notice that was hidden behind it
    /// gets its full window now.
    private func promptVisibilityChanged() {
        let available = isPromptAvailable
        defer { promptWasAvailable = available }
        guard promptWasAvailable, !available, notice.isVisible else { return }
        notice.release(now: Date())
        scheduleNoticeExpiry()
    }

    private func showPanelError(_ failure: PanelFailure) {
        panelError.show(failure.message, now: Date())
        panelErrorTask?.cancel()
        let delay = PanelError.window
        panelErrorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.panelError.expireIfDue(now: Date())
        }
    }

    // MARK: Prompt actions

    /// `id` is the file the prompt showed when the user acted; the action is ignored if the prompt moved on.
    /// Also ignored while a previous decision is still running, so a double click never acts on the same files
    /// twice. On failure the prompt stays and the panel shows the error.
    func decide(for id: FileID) async {
        guard !isDeciding else { return }
        let ids = queue.targets(for: id, applyToAll: applyToAll)
        guard !ids.isEmpty else { return }
        isDeciding = true
        defer { isDeciding = false }
        let succeeded: Bool
        switch timeline.selected {
        case .keep: succeeded = await perform(.update) { try await $0.keep(ids: ids, recordChoice: true) }
        case .duration(let duration):
            succeeded = await perform(.update) {
                try await $0.schedule(ids: ids, duration: duration, recordChoice: true)
            }
        }
        if succeeded { await finishDecision(ids) }
    }

    func keepPrompted(for id: FileID) async {
        guard !isDeciding else { return }
        let ids = queue.targets(for: id, applyToAll: applyToAll)
        guard !ids.isEmpty else { return }
        isDeciding = true
        defer { isDeciding = false }
        if await perform(.update, { try await $0.keep(ids: ids, recordChoice: true) }) {
            await finishDecision(ids)
        }
    }

    /// Moves the prompt on right away instead of waiting for the file observation to catch up.
    private func finishDecision(_ ids: [FileID]) async {
        await refreshState()  // the recorded choice may change the next preselection
        queue.dismiss(ids: ids)
        if queue.current == nil { promptRequested = false }
        resetPromptState()
        promptVisibilityChanged()
    }

    /// Opens the prompt for a waiting file picked from the list, even one closed with Esc and even in Quiet
    /// mode. Requests nothing when the file is no longer pending, so the next download can't bypass Quiet mode.
    func review(_ id: FileID) {
        let previous = queue.current?.id
        queue.restore(ids: [id], pending: pending)
        if queue.current?.id != previous { resetPromptState() }
        promptRequested = queue.current?.id == id
        promptVisibilityChanged()
    }

    /// Esc: closes the prompt without deciding. In Quiet mode it stays closed for the rest of the stack too.
    func dismissPrompt() {
        queue.dismiss(applyToAll: applyToAll)
        promptRequested = false
        resetPromptState()
        promptVisibilityChanged()
    }

    // MARK: File actions

    func keep(_ ids: [FileID]) async { await perform(.update) { try await $0.keep(ids: ids) } }

    func schedule(_ ids: [FileID], duration: TimeInterval) async {
        await perform(.update) { try await $0.schedule(ids: ids, duration: duration) }
    }

    /// The notice goes away only when Undo worked; after a failure it stays, so Undo can be tried again.
    func undoNotice() async {
        let ids = notice.files.map(\.id)
        guard !ids.isEmpty else { return }
        if await perform(.undo, { try await $0.undoTrash(ids: ids) }) {
            // A trash merged in meanwhile keeps its notice.
            notice.remove(ids: ids)
        }
    }

    func retry(_ ids: [FileID]) async { await perform(.retry) { try await $0.retry(ids: ids) } }

    /// Disposes of the files now, like an expiry (Trash or permanent, per Settings); the notice offers Undo.
    func deleteNow(_ ids: [FileID]) async { await perform(.delete) { try await $0.deleteNow(ids: ids) } }

    // MARK: Folders & settings

    @discardableResult
    func addFolder(_ url: URL) async -> Bool {
        var added = false
        await perform { engine in
            _ = try await engine.addFolder(path: url.path)
            added = true
        }
        await refreshState()
        return added
    }

    func removeFolder(id: Int64) async {
        let path = folders.first { $0.id == id }?.path
        if await perform(nil, { try await $0.removeFolder(id: id) }), let path {
            EngineBootstrap.forgetFolder(path: path, defaults: defaults)
        }
        await refreshState()
    }

    func update(_ newSettings: Settings) async {
        let loginChanged = newSettings.launchAtLogin != settings.launchAtLogin
        await perform { try await $0.updateSettings(newSettings) }
        await refreshState()
        scheduleClock()  // the reminder settings may have changed what is due
        promptVisibilityChanged()  // e.g. Quiet mode turned on while the prompt was open
        if loginChanged { applyLoginItem(settings.launchAtLogin) }
        let fresh = TimelineModel(durations: settings.timelineStops, preselect: resolvedChoice)
        if timeline.stops != fresh.stops { resetPromptState() }
    }

    func clearHistory() async -> Int? {
        guard let engine else { return nil }
        do {
            return try await engine.clearHistory()
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Helpers

    /// Runs an engine action and reports its error; returns whether it succeeded. With `failure`, the error is
    /// also shown in the panel (prompt, list and notice actions), because the user is looking there.
    @discardableResult
    private func perform(
        _ failure: PanelFailure? = nil, _ action: (DropKeeperEngine) async throws -> Void
    ) async -> Bool {
        do {
            guard let engine else { throw NotStartedError() }
            try await action(engine)
            return true
        } catch {
            report(error)
            if let failure { showPanelError(failure) }
            return false
        }
    }

    private func report(_ error: any Error) {
        log.error("Engine action failed: \(String(describing: error), privacy: .private)")
        lastError = ErrorText.message(for: error)
    }
}

/// An action before the engine started (or after it failed to start).
private struct NotStartedError: Error {}

enum ErrorText {
    static func message(for error: any Error) -> String {
        switch error as? EngineError {
        case .notADirectory: String(localized: "That item is not a folder.")
        case .invalidFolder: String(localized: "That folder can't be watched.")
        case .overlapsExistingFolder:
            String(localized: "That folder is inside, or contains, a folder that is already watched.")
        case .partialFailure(let ids): String(localized: "\(ids.count) files could not be updated.")
        case nil: String(localized: "Something went wrong. Please try again.")
        }
    }
}
