import DropKeeperCore
import SwiftUI

/// What the stack shows: the reminder, the rule notice and the trash notice (each may be empty).
struct NoticeStackContent: Equatable {
    var reminders: [TrackedFile] = []
    var rules: [RuleApplication] = []
    var trashed: [TrackedFile] = []

    var isEmpty: Bool { reminders.isEmpty && rules.isEmpty && trashed.isEmpty }

    /// The current bars; while none is left and the panel is still fading out (`holdsLast`), the last non-empty
    /// content, so the panel doesn't empty out before it is gone.
    static func resolve(current: Self, last: Self, holdsLast: Bool) -> Self {
        current.isEmpty && holdsLast ? last : current
    }
}

/// The bars above the prompt, top to bottom: pre-expiry reminder, rule notice, "Moved to Trash" notice.
/// None of them takes keyboard focus, so the prompt below keeps its focus, selection and Return.
struct NoticeStackView: View {
    let model: AppModel
    /// The panel shows only this stack: its last content then stays on screen while the panel fades out.
    let holdsNotice: Bool
    @State private var last = NoticeStackContent()

    private var current: NoticeStackContent {
        NoticeStackContent(
            reminders: model.reminders.due, rules: model.ruleNotice.items, trashed: model.notice.items)
    }

    var body: some View {
        let shown = NoticeStackContent.resolve(current: current, last: last, holdsLast: holdsNotice)
        VStack(spacing: 0) {
            if !shown.reminders.isEmpty {
                ReminderBarView(
                    files: shown.reminders,
                    onExtend: { Task { await model.extendReminders() } },
                    onKeep: { Task { await model.keepReminders() } },
                    onDelete: { Task { await model.deleteReminders() } },
                    onDismiss: { model.dismissReminders() })
            }
            if !shown.rules.isEmpty {
                if !shown.reminders.isEmpty { separator }
                RuleNoticeView(
                    applications: shown.rules, rules: model.settings.rules, onChange: { model.changeRuleNotice() },
                    onHover: { inside in
                        if inside { model.pauseRuleNotice() } else { model.resumeRuleNotice() }
                    })
            }
            if !shown.trashed.isEmpty {
                if !shown.reminders.isEmpty || !shown.rules.isEmpty { separator }
                NoticeView(
                    files: shown.trashed, canUndo: model.settings.deleteMode == .trash,
                    onUndo: { Task { await model.undoNotice() } })
            }
        }
        .onChange(of: current, initial: true) { _, new in
            if !new.isEmpty { last = new }
        }
    }

    private var separator: some View {
        Rectangle().fill(TK.Notch.hairline).frame(height: 1)
    }
}
