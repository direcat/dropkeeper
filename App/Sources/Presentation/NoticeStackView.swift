import DropKeeperCore
import SwiftUI

/// The bars above the prompt, top to bottom: pre-expiry reminder, rule notice, "Moved to Trash" notice.
/// None of them takes keyboard focus, so the prompt below keeps its focus, selection and Return.
struct NoticeStackView: View {
    let model: AppModel
    /// The panel shows only this stack: the trash notice then stays on screen while the panel fades out.
    let holdsNotice: Bool
    @State private var hadNotice = false

    private var showsReminder: Bool { !model.reminders.due.isEmpty }
    private var showsRule: Bool { model.ruleNotice.isVisible }
    private var showsNotice: Bool {
        model.notice.isVisible || (holdsNotice && hadNotice && !showsReminder && !showsRule)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsReminder {
                ReminderBarView(
                    files: model.reminders.due,
                    onExtend: { Task { await model.extendReminders() } },
                    onKeep: { Task { await model.keepReminders() } },
                    onDelete: { Task { await model.deleteReminders() } },
                    onDismiss: { model.dismissReminders() })
            }
            if showsRule {
                if showsReminder { separator }
                RuleNoticeView(
                    applications: model.ruleNotice.items, onChange: { model.changeRuleNotice() },
                    onHover: { inside in
                        if inside { model.pauseRuleNotice() } else { model.resumeRuleNotice() }
                    })
            }
            if showsNotice {
                if showsReminder || showsRule { separator }
                NoticeView(
                    files: model.notice.items, canUndo: model.settings.deleteMode == .trash,
                    onUndo: { Task { await model.undoNotice() } })
            }
        }
        .onChange(of: model.notice.isVisible, initial: true) { _, visible in
            if visible { hadNotice = true }
        }
    }

    private var separator: some View {
        Rectangle().fill(TK.Notch.hairline).frame(height: 1)
    }
}
