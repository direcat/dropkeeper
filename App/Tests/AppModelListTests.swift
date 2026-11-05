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

/// A scheduled file inside its reminder window (30 min timer, 2 min left).
private func dueFile(_ id: String) -> TrackedFile {
    var file = scheduledFile(expiresIn: 0, id: id)
    file.updatedAt = Date().addingTimeInterval(-3480)
    file.expiresAt = Date().addingTimeInterval(120)
    return file
}

/// How the menu bar list and the reminder countdown interact with the model; the engine is never involved.
@MainActor
@Suite(.serialized) struct AppModelListTests {
    private final class Clock {
        var now = Date()
    }

    @MainActor
    private struct Fixture {
        let model: AppModel
        let clock = Clock()
        let suite = "AppModelListTests.\(UUID().uuidString)"

        init() {
            model = AppModel(defaults: UserDefaults(suiteName: suite)!, applyLoginItem: { _ in })
            model.isVoiceOverRunning = { false }
            let clock = clock
            model.clock = { clock.now }
        }

        func cleanUp() {
            model.autoHide.cancelTasks()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    @Test func newFileEnteringTheReminderRestartsItsCountdown() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let clock = fixture.clock
        let first = dueFile("a.dmg")
        model.apply([first])
        clock.now += 10
        #expect(model.reminderTimer.remaining(now: clock.now) == 20)
        let second = dueFile("b.dmg")
        model.apply([first, second])
        #expect(model.reminderTimer.remaining(now: clock.now) == 30)
        clock.now += 5
        model.apply([first, second])  // unrelated update: no restart
        #expect(model.reminderTimer.remaining(now: clock.now) == 25)
    }

    // MARK: Menu bar list

    @Test func openListHidesPromptAndDropsNotices() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a")])
        #expect(model.isPromptAvailable)
        model.isListOpen = true
        #expect(!model.isPromptAvailable)
        await model.handle(.trashed([pendingFile("gone")]))
        #expect(!model.notice.isVisible)
        let application = RuleApplication(file: pendingFile("r"), ruleId: UUID(), ruleName: "Rule")
        await model.handle(.ruleApplied([application]))
        #expect(!model.ruleNotice.isVisible)
    }

    @Test func openListStopsTimersAndClosingStartsThemFresh() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let clock = fixture.clock
        model.apply([pendingFile("a")])
        #expect(model.promptTimer.remaining(now: clock.now) == 30)
        clock.now += 20
        model.isListOpen = true
        #expect(model.promptTimer.remaining(now: clock.now) == nil)
        clock.now += 100
        model.isListOpen = false
        #expect(model.queue.current?.id == "a")  // nothing was dismissed
        #expect(model.promptTimer.remaining(now: clock.now) == 30)
    }

    @Test func openListStopsTheReminderTimerAndClosingRestartsIt() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let clock = fixture.clock
        model.apply([dueFile("due.dmg")])
        #expect(model.reminderTimer.remaining(now: clock.now) != nil)
        model.isListOpen = true
        #expect(model.reminderTimer.remaining(now: clock.now) == nil)
        #expect(model.reminders.due.count == 1)  // still due, just not counting down
        clock.now += 50
        model.isListOpen = false
        #expect(model.reminderTimer.remaining(now: clock.now) == 30)
    }

    @Test func closingListLetsPendingPromptShowAgain() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a")])
        model.isListOpen = true
        model.isListOpen = false
        #expect(model.isPromptAvailable)
    }

    @Test func fileDismissedBeforeTheListOpenedStaysHiddenAfterClose() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a")])
        model.dismissPrompt()
        model.isListOpen = true
        model.isListOpen = false
        #expect(!model.isPromptAvailable)
        #expect(model.pending.count == 1)  // still waiting, reachable from the list
    }

    @Test func fileTimedOutBeforeTheListOpenedStaysHiddenAfterClose() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.apply([pendingFile("a")])
        fixture.clock.now += 31
        model.expireAutoHideTimers()
        model.isListOpen = true
        model.isListOpen = false
        #expect(!model.isPromptAvailable)
    }

    @Test func fileArrivingWhileTheListIsOpenWaitsForClose() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.isListOpen = true
        model.apply([pendingFile("new")])
        #expect(!model.isPromptAvailable)
        #expect(model.promptTimer.remaining(now: fixture.clock.now) == nil)
        model.isListOpen = false
        #expect(model.isPromptAvailable)
        #expect(model.promptTimer.remaining(now: fixture.clock.now) == 30)
    }
}
