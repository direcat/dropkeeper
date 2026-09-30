import DropKeeperCore
import Foundation
import SwiftUI
import Testing

@testable import DropKeeper

@Test func rowsShowFailedThenPendingThenSoonestScheduled() {
    let later = scheduledFile(expiresIn: 600, id: "later")
    let sooner = scheduledFile(expiresIn: 60, id: "sooner")
    var failedFile = scheduledFile(expiresIn: 0, id: "failed")
    failedFile.state = .failed
    var pendingFile = scheduledFile(expiresIn: 0, id: "pending")
    pendingFile.state = .pending
    let rows = PendingRows.ordered(pending: [pendingFile], scheduled: [later, sooner], failed: [failedFile])
    #expect(rows.map(\.id) == ["failed", "pending", "sooner", "later"])
}

@Test func statusIconStates() {
    #expect(StatusIcon.state(hasProblems: true, quietMode: true, hasPending: true) == .warning)
    #expect(StatusIcon.state(hasProblems: false, quietMode: true, hasPending: true) == .attention)
    #expect(StatusIcon.state(hasProblems: false, quietMode: false, hasPending: true) == .idle)
    #expect(StatusIcon.warning.imageName == "MenuBarWarning")
}

@Test func statusTitles() {
    #expect(StatusTitle.make(scheduledCount: 0, urgentSeconds: nil) == .none)
    #expect(StatusTitle.make(scheduledCount: 3, urgentSeconds: nil) == .count(3))
    #expect(StatusTitle.make(scheduledCount: 3, urgentSeconds: 7) == .countdown(7))
}

@MainActor
@Test func pendingListRendersEmptyAndFilled() {
    let suiteName = "PendingListTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    let actions = AppActions(openSettings: {}, quit: {}, review: { _ in })
    #expect(ImageRenderer(content: PendingListView(model: model, actions: actions)).cgImage != nil)
    var failedFile = scheduledFile(expiresIn: 0, id: "failed")
    failedFile.state = .failed
    model.apply([scheduledFile(expiresIn: 60, id: "sooner"), failedFile])
    let view = PendingListView(model: model, actions: actions, showsFooter: false)
    #expect(ImageRenderer(content: view).cgImage != nil)
}
