import DropKeeperCore
import Foundation

/// The two notification countdowns and what they belong to.
struct AutoHideState {
    var prompt = AutoHideTimer(duration: Settings().notificationTimeout)
    var reminder = AutoHideTimer(duration: Settings().notificationTimeout)
    /// What the running prompt countdown belongs to (current file and stack size); a change restarts it.
    struct PromptKey: Equatable {
        let current: FileID
        let count: Int
    }
    var promptKey: PromptKey?
    var reminderIds: Set<FileID> = []
    var isPanelHovered = false
    var promptTask: Task<Void, Never>?
    var reminderTask: Task<Void, Never>?

    func cancelTasks() {
        promptTask?.cancel()
        reminderTask?.cancel()
    }
}

extension AppModel {
    var promptTimer: AutoHideTimer { autoHide.prompt }
    var reminderTimer: AutoHideTimer { autoHide.reminder }

    /// Whole seconds are shown, so the bar and the caption follow the same clock.
    var promptHideSeconds: Int? {
        promptTimer.remaining(now: clock()).map { Int($0.rounded(.up)) }
    }

    /// Remaining share (0...1) of the prompt's countdown; nil when it doesn't hide by itself.
    var promptHideProgress: Double? {
        guard let remaining = promptTimer.remaining(now: clock()), promptTimer.duration > 0 else { return nil }
        return min(max(remaining / promptTimer.duration, 0), 1)
    }

    /// Brings both timers in line with what is on screen: a prompt or a reminder that appears (or gains a file)
    /// starts a full countdown; one that is gone, exempt or switched off stops it.
    func syncAutoHide() {
        let now = clock()
        let timeout = settings.notificationTimeout
        let hidesByItself = timeout > 0 && !isVoiceOverRunning()
        var state = autoHide

        if state.prompt.duration != timeout {
            state.prompt = AutoHideTimer(duration: timeout)
            state.promptKey = nil
        }
        if hidesByItself, isPromptAvailable, !queue.isRevisiting, let current = queue.current,
            requestedFileId != current.id
        {
            let key = AutoHideState.PromptKey(current: current.id, count: queue.items.count)
            if key != state.promptKey || state.prompt.remaining(now: now) == nil {
                state.prompt.start(now: now)
                if state.isPanelHovered { state.prompt.pause(now: now) }
                state.promptKey = key
            }
        } else {
            state.prompt.stop()
            state.promptKey = nil
        }

        if state.reminder.duration != timeout {
            state.reminder = AutoHideTimer(duration: timeout)
            state.reminderIds = []
        }
        let due = Set(reminders.due.map(\.id))
        if hidesByItself, !due.isEmpty {
            if !due.isSubset(of: state.reminderIds) || state.reminder.remaining(now: now) == nil {
                state.reminder.start(now: now)
                if state.isPanelHovered { state.reminder.pause(now: now) }
            }
            state.reminderIds = due
        } else {
            state.reminder.stop()
            state.reminderIds = []
        }
        autoHide = state
        scheduleAutoHideExpiry()
    }

    private func scheduleAutoHideExpiry() {
        autoHide.cancelTasks()
        let now = clock()
        autoHide.promptTask = expiryTask(at: autoHide.prompt.expiresAt, now: now)
        autoHide.reminderTask = expiryTask(at: autoHide.reminder.expiresAt, now: now)
    }

    private func expiryTask(at expiresAt: Date?, now: Date) -> Task<Void, Never>? {
        guard let expiresAt else { return nil }
        let delay = max(0, expiresAt.timeIntervalSince(now))
        return Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expireAutoHideTimers()
        }
    }

    /// Hides what is due: the prompt like Esc for the whole visible stack (the files stay pending), the reminder
    /// like its close button.
    func expireAutoHideTimers() {
        let now = clock()
        if autoHide.prompt.isDue(now: now) { dismissPromptStack() }
        if autoHide.reminder.isDue(now: now) { dismissReminders() }
        syncAutoHide()
    }

    /// The pointer is over the panel: both countdowns hold still.
    func pausePanelTimers() {
        autoHide.isPanelHovered = true
        let now = clock()
        autoHide.prompt.pause(now: now)
        autoHide.reminder.pause(now: now)
        scheduleAutoHideExpiry()
    }

    func resumePanelTimers() {
        autoHide.isPanelHovered = false
        let now = clock()
        autoHide.prompt.resume(now: now)
        autoHide.reminder.resume(now: now)
        scheduleAutoHideExpiry()
    }

    /// A key press the prompt handled counts as attention: the countdown starts over.
    func noteKeyActivity() {
        let now = clock()
        guard autoHide.prompt.remaining(now: now) != nil else { return }
        autoHide.prompt.restart(now: now)
        scheduleAutoHideExpiry()
    }
}
