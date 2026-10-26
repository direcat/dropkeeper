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
