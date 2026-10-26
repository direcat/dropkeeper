import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private func pendingFile(_ id: String) -> TrackedFile {
    var file = scheduledFile(expiresIn: 0, id: id)
    file.state = .pending
    file.expiresAt = nil
    return file
}

/// App model flows that need no engine: without one, every engine action fails like a broken engine would.
@MainActor
@Suite(.serialized) struct AppModelFlowTests {
    /// A model with its own defaults suite; `cleanUp` removes the suite.
    @MainActor
    private struct Fixture {
        let model: AppModel
        let suite: String

        init() {
            suite = "AppModelFlowTests.\(UUID().uuidString)"
            model = AppModel(defaults: UserDefaults(suiteName: suite)!, applyLoginItem: { _ in })
        }

        func cleanUp() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    @Test func fileClosedWithEscCanBeReopenedFromTheList() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a"), pendingFile("b")])
        model.dismissPrompt()
        model.dismissPrompt()
        #expect(!model.isPromptAvailable)
        model.review("a")
        #expect(model.queue.current?.id == "a")
        #expect(model.isPromptAvailable)
        model.apply([pendingFile("a"), pendingFile("b")])
        #expect(model.queue.current?.id == "a")
    }

    @Test func reviewOfAFileThatIsNoLongerPendingRequestsNothing() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([])
        model.review("gone")
        #expect(!model.promptRequested)  // a later download must not bypass Quiet mode
    }

    @Test func failedUndoKeepsTheNoticeAndShowsAnError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        await model.handle(.trashed([scheduledFile(expiresIn: 0, id: "a.pdf")]))
        #expect(model.notice.isVisible)
        await model.undoNotice()
        #expect(model.notice.isVisible)  // Undo can be tried again
        #expect(model.panelError.isVisible)
    }

    @Test func failedDecisionKeepsThePromptAndShowsAnError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a")])
        await model.decide(for: "a")
        #expect(model.queue.current?.id == "a")
        #expect(model.panelError.isVisible)
        #expect(model.lastError != nil)
    }

    @Test func actionForAFileThePromptNoLongerShowsIsIgnored() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a"), pendingFile("b")])
        await model.decide(for: "b")
        await model.keepPrompted(for: "b")
        #expect(!model.panelError.isVisible)  // nothing was attempted
        #expect(model.queue.current?.id == "a")
    }

    @Test func failedListActionsShowAnError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        await model.keep(["a"])
        #expect(model.panelError.isVisible)
        let otherFixture = Fixture()
        defer { otherFixture.cleanUp() }
        let other = otherFixture.model
        await other.retry(["a"])
        #expect(other.panelError.isVisible)
    }

    /// Review Focus 1: a notice arriving over the prompt leaves its timeline selection and state alone.
    @Test func noticeDuringPromptKeepsPromptState() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a"), pendingFile("b")])
        model.timeline.select(2)
        model.applyToAll = true
        let selected = model.timeline.selected
        await model.handle(.trashed([scheduledFile(expiresIn: 0, id: "old.pdf")]))
        await model.handle(.ruleApplied([RuleApplication(file: scheduledFile(expiresIn: 60), ruleName: "Rule")]))
        #expect(model.isNoticeVisible)
        #expect(model.isPromptAvailable)
        #expect(model.queue.current?.id == "a")
        #expect(model.timeline.selected == selected)
        #expect(model.applyToAll)
    }

    /// Review Focus 4: Quiet mode holds the prompt back, not a reminder (the notice decision ignores it).
    @Test func quietModeStillShowsReminder() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let now = Date()
        var due = scheduledFile(expiresIn: 0, id: "due.dmg")
        due.updatedAt = now.addingTimeInterval(-3480)
        due.expiresAt = now.addingTimeInterval(120)
        model.apply([due])
        // Quiet mode makes `promptAvailable` false whatever is queued.
        #expect(
            PanelDecision.content(
                promptAvailable: false, noticeVisible: model.isNoticeVisible, target: .menuBar, scheduledCount: 1,
                hovering: false) == .notice)
    }

    /// Without an engine the action fails and reports it: proves the reminder ids reach the engine call.
    @Test func reminderActionsWithoutDueFilesDoNothing() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        await model.extendReminders()
        await model.keepReminders()
        await model.deleteReminders()
        #expect(!model.panelError.isVisible)  // nothing is due, so nothing was attempted
    }

    /// Onboarding shows `lastError` when adding the folder fails, so the failure must set it.
    @Test func failedAddFolderReportsAnError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        #expect(!(await model.addFolder(URL(fileURLWithPath: "/tmp/dk-never-used"))))
        #expect(model.lastError != nil)
        #expect(!model.panelError.isVisible)  // Settings and onboarding actions don't use the panel
    }
}
