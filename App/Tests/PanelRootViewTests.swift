import AppKit
import SwiftUI
import Testing

@testable import DropKeeper

@MainActor
@Test func panelRootRendersEveryContent() async {
    let suiteName = "PanelRootViewTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    await model.handle(.trashed([scheduledFile(expiresIn: 0, id: "a.pdf")]))  // the notice stack needs a bar
    for content in [PanelContent.notice, .hidden] {
        let view = PanelRootView(model: model, content: content)
        #expect(ImageRenderer(content: view).cgImage != nil || content == .hidden)
    }
}

/// A reminder above the prompt grows the panel; the prompt is still there.
@MainActor
@Test func promptWithNoticeRendersBoth() {
    let suiteName = "PanelRootViewBothTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    var pending = scheduledFile(expiresIn: 0, id: "Quarterly report.pdf")
    pending.state = .pending
    pending.expiresAt = nil
    model.apply([pending])
    func height() -> CGFloat {
        let view = PanelRootView(model: model, content: .prompt)
        return NSHostingView(rootView: view).fittingSize.height
    }
    let promptAlone = height()
    var due = scheduledFile(expiresIn: 0, id: "Installer.dmg")
    let now = Date()
    due.updatedAt = now.addingTimeInterval(-3480)
    due.expiresAt = now.addingTimeInterval(120)
    model.apply([pending, due])
    #expect(model.reminders.due.count == 1)
    #expect(height() > promptAlone)
}

/// Reported sequence: a trash notice ended, a reminder came and went. While fading out, the stack must show the
/// reminder it last had, never an empty "0 files" trash notice.
@Test func fadingStackShowsItsLastContentNotAFabricatedNotice() {
    let reminder = NoticeStackContent(reminders: [scheduledFile(expiresIn: 60, id: "due.dmg")])
    let empty = NoticeStackContent()
    let shown = NoticeStackContent.resolve(current: empty, last: reminder, holdsLast: true)
    #expect(shown == reminder)
    #expect(shown.trashed.isEmpty)
    #expect(NoticeStackContent.resolve(current: empty, last: reminder, holdsLast: false).isEmpty)
    let live = NoticeStackContent(trashed: [scheduledFile(expiresIn: 0, id: "a.pdf")])
    #expect(NoticeStackContent.resolve(current: live, last: reminder, holdsLast: true) == live)
}
