import CoreGraphics
import DropKeeperCore
import SwiftUI
import Testing

@testable import DropKeeper

@Test func openPanelKeepsItsMenuBarAnchorWhileTheStatusItemMoves() {
    let opened = CGRect(x: 1501, y: 0, width: 24, height: 24)
    let shifted = CGRect(x: 1543, y: 0, width: 24, height: 24)
    // A re-render of the same prompt happens after other menu bar items moved the status item.
    #expect(PanelDecision.anchor(previous: .prompt, next: .prompt, locked: opened, current: shifted) == opened)
    #expect(PanelDecision.anchor(previous: .prompt, next: .notice, locked: opened, current: shifted) == opened)
    // First render, or the panel was hidden: take the current anchor.
    #expect(PanelDecision.anchor(previous: .hidden, next: .prompt, locked: opened, current: shifted) == shifted)
    #expect(PanelDecision.anchor(previous: .prompt, next: .prompt, locked: nil, current: shifted) == shifted)
}

@Test func menuBarPanelStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let anchor = CGRect(x: 1480, y: 950, width: 24, height: 32)
    let frame = PanelGeometry.menuBarPanelFrame(
        anchor: anchor, visibleFrame: visible, size: CGSize(width: TK.Size.panelWidth, height: 132))
    #expect(frame.maxX == 1504)  // 8 pt margin
    #expect(frame.maxY == 944)  // 6 pt under the menu bar item
}

@Test(arguments: [
    (true, true, true, PanelContent.prompt), (false, true, true, .notice),
    (false, false, true, .error), (false, false, false, .hidden),
])
func panelContentPriority(prompt: Bool, notice: Bool, error: Bool, expected: PanelContent) {
    #expect(PanelDecision.content(promptAvailable: prompt, noticeVisible: notice, errorVisible: error) == expected)
}

/// A scheduled file inside its reminder window: its 1 h timer ends in two minutes, the lead time is five.
private func dueFile(_ id: String) -> TrackedFile {
    var file = scheduledFile(expiresIn: 0, id: id)
    let now = Date()
    file.updatedAt = now.addingTimeInterval(-3480)
    file.expiresAt = now.addingTimeInterval(120)
    return file
}

@MainActor
@Test func reminderMakesNoticeVisible() {
    let suite = "PresentationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    #expect(!model.isNoticeVisible)
    model.apply([dueFile("a.pdf")])
    #expect(model.reminders.due.count == 1)
    #expect(model.isNoticeVisible)
    #expect(
        PanelDecision.content(
            promptAvailable: false, noticeVisible: model.isNoticeVisible, errorVisible: false) == .notice)
}

@Test func showNeverSkipsWhileTheHideFadeIsRunning() {
    #expect(PanelDecision.showStep(isOnScreen: false, isFadingOut: false, frameChanged: false) == .fadeIn)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: true, frameChanged: false) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: true, frameChanged: true) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: false, frameChanged: true) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: false, frameChanged: false) == .none)
}

@Test func panelSlidesDownFromAboveAndResizesOnlyInPlace() {
    let final = CGRect(x: 100, y: 500, width: 320, height: 200)
    let start = PanelGeometry.slideStartFrame(for: final, offset: 18)
    #expect(start == CGRect(x: 100, y: 518, width: 320, height: 200))
    let taller = CGRect(x: 100, y: 450, width: 320, height: 250)  // same top edge
    let otherAnchor = CGRect(x: 900, y: 500, width: 320, height: 200)
    let otherTop = CGRect(x: 100, y: 100, width: 320, height: 200)
    #expect(PanelGeometry.resizesInPlace(from: final, to: taller))
    #expect(!PanelGeometry.resizesInPlace(from: final, to: otherAnchor))
    #expect(!PanelGeometry.resizesInPlace(from: final, to: otherTop))
}
