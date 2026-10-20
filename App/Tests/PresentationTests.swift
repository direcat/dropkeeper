import CoreGraphics
import DropKeeperCore
import SwiftUI
import Testing

@testable import DropKeeper

private let notch = CGRect(x: 656, y: 950, width: 200, height: 32)
private let builtIn = ScreenDescriptor(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
    isBuiltIn: true, isPrimary: true, notchRect: notch, containsPointer: true)
private let external = ScreenDescriptor(
    id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
    isBuiltIn: false, isPrimary: false, notchRect: nil, containsPointer: false)

private func with(_ screen: ScreenDescriptor, primary: Bool? = nil, pointer: Bool? = nil) -> ScreenDescriptor {
    ScreenDescriptor(
        id: screen.id, frame: screen.frame, visibleFrame: screen.visibleFrame, isBuiltIn: screen.isBuiltIn,
        isPrimary: primary ?? screen.isPrimary, notchRect: screen.notchRect,
        containsPointer: pointer ?? screen.containsPointer)
}

@Test func automaticUsesNotchWhenThePointerIsOnTheNotchedLaptop() {
    #expect(PresentationResolver.resolve(.automatic, screens: [builtIn]) == .notch(builtIn))
    #expect(PresentationResolver.resolve(.automatic, screens: [builtIn, external]) == .notch(builtIn))
    // External primary, lid open: the pointer decides, not the menu bar.
    let laptop = with(builtIn, primary: false)
    #expect(
        PresentationResolver.resolve(.automatic, screens: [with(external, primary: true), laptop]) == .notch(laptop))
}

@Test func automaticUsesMenuBarWhenThePointerIsOnAnotherDisplay() {
    let screens = [with(external, primary: true, pointer: true), with(builtIn, primary: false, pointer: false)]
    #expect(PresentationResolver.resolve(.automatic, screens: screens) == .menuBar)
    // Laptop primary, pointer on the external display.
    #expect(
        PresentationResolver.resolve(
            .automatic, screens: [with(builtIn, pointer: false), with(external, pointer: true)])
            == .menuBar)
}

@Test func reviewFocusClosedLidOrExternalPrimaryUsesMenuBar() {
    let lidClosed = [with(external, primary: true, pointer: true)]
    #expect(PresentationResolver.resolve(.automatic, screens: lidClosed) == .menuBar)
    #expect(PresentationResolver.resolve(.notch, screens: lidClosed) == .menuBar)
    let externalMain = [with(external, primary: true, pointer: true), with(builtIn, primary: false, pointer: false)]
    #expect(PresentationResolver.resolve(.notch, screens: externalMain) == .notch(externalMain[1]))
}

@Test func closedNotchShowsOnTheNotchedDisplayWhereverThePointerIs() {
    let laptop = with(builtIn, primary: false, pointer: false)
    let externalMain = [with(external, primary: true, pointer: true), laptop]
    #expect(PresentationResolver.idleTarget(.automatic, screens: externalMain) == .notch(laptop))
    #expect(PresentationResolver.idleTarget(.notch, screens: externalMain) == .notch(laptop))
    #expect(PresentationResolver.idleTarget(.menuBar, screens: externalMain) == .menuBar)
    let lidClosed = [with(external, primary: true, pointer: true)]
    for setting in [PromptPresentation.automatic, .notch, .menuBar] {
        #expect(PresentationResolver.idleTarget(setting, screens: lidClosed) == .menuBar)
    }
}

@Test func pointerHitTestIncludesTheTopEdgeButNotTheSharedRightEdge() {
    let frame = CGRect(x: -1470, y: -250, width: 1470, height: 956)
    #expect(NotchGeometry.contains(CGPoint(x: -735, y: 0), frame: frame))
    #expect(NotchGeometry.contains(CGPoint(x: -735, y: 706), frame: frame))  // top row reports maxY
    #expect(NotchGeometry.contains(CGPoint(x: -1470, y: -250), frame: frame))
    #expect(!NotchGeometry.contains(CGPoint(x: 0, y: 100), frame: frame))  // belongs to the display on the right
    #expect(!NotchGeometry.contains(CGPoint(x: 100, y: 100), frame: frame))
    #expect(!NotchGeometry.contains(CGPoint(x: -735, y: 707), frame: frame))
}

@Test func rightmostDisplayOwnsItsRightEdge() {
    let builtIn = CGRect(x: 0, y: 0, width: 1470, height: 956)
    #expect(NotchGeometry.contains(CGPoint(x: 1470, y: 100), frame: builtIn, isRightmost: true))
    #expect(!NotchGeometry.contains(CGPoint(x: 1470, y: 100), frame: builtIn, isRightmost: false))
    #expect(!NotchGeometry.contains(CGPoint(x: 1471, y: 100), frame: builtIn, isRightmost: true))
}

@Test func openPanelKeepsItsTargetUntilItWasHiddenOrIdle() {
    let open: [PanelContent] = [.prompt, .notice, .error]
    for previous in open {
        for next in open { #expect(PanelDecision.keepsTarget(previous: previous, next: next)) }
    }
    for previous in [PanelContent.hidden, .idle, .idleExpanded] {
        for next in open { #expect(!PanelDecision.keepsTarget(previous: previous, next: next)) }
    }
    // The closed notch and its list always use the idle target.
    for next in [PanelContent.hidden, .idle, .idleExpanded] {
        #expect(!PanelDecision.keepsTarget(previous: .prompt, next: next))
    }
}

@Test func lockedTargetSurvivesPointerMovesButNotALostDisplay() {
    let laptop = with(builtIn, primary: false, pointer: false)
    let pointerOnExternal = [with(external, primary: true, pointer: true), laptop]
    // Prompt opened in the notch, then the pointer moved to the external display.
    #expect(
        PanelDecision.target(
            previous: .prompt, next: .prompt, locked: .notch(builtIn), resolved: .menuBar, screens: pointerOnExternal)
            == .notch(laptop))
    // Prompt opened under the menu bar icon, then the pointer moved to the laptop.
    #expect(
        PanelDecision.target(
            previous: .prompt, next: .notice, locked: .menuBar, resolved: .notch(builtIn), screens: [builtIn, external])
            == .menuBar)
    // Lid closed while the prompt was in the notch.
    #expect(
        PanelDecision.target(
            previous: .prompt, next: .prompt, locked: .notch(builtIn), resolved: .menuBar,
            screens: [with(external, primary: true, pointer: true)]) == .menuBar)
    // Panel was hidden: resolve again.
    #expect(
        PanelDecision.target(
            previous: .hidden, next: .prompt, locked: .menuBar, resolved: .notch(builtIn), screens: [builtIn])
            == .notch(builtIn))
    #expect(
        PanelDecision.target(previous: .prompt, next: .prompt, locked: nil, resolved: .menuBar, screens: [builtIn])
            == .menuBar)
}

@Test func openPanelKeepsItsMenuBarAnchorWhileTheStatusItemMoves() {
    let opened = CGRect(x: 1501, y: 0, width: 24, height: 24)
    let shifted = CGRect(x: 1543, y: 0, width: 24, height: 24)
    // Hover re-renders the same prompt after other menu bar items moved the status item.
    #expect(PanelDecision.anchor(previous: .prompt, next: .prompt, locked: opened, current: shifted) == opened)
    #expect(PanelDecision.anchor(previous: .prompt, next: .notice, locked: opened, current: shifted) == opened)
    // First render, or the panel was hidden or idle: take the current anchor.
    #expect(PanelDecision.anchor(previous: .hidden, next: .prompt, locked: opened, current: shifted) == shifted)
    #expect(PanelDecision.anchor(previous: .idle, next: .prompt, locked: opened, current: shifted) == shifted)
    #expect(PanelDecision.anchor(previous: .prompt, next: .prompt, locked: nil, current: shifted) == shifted)
}

@Test func menuBarSettingAlwaysUsesMenuBar() {
    #expect(PresentationResolver.resolve(.menuBar, screens: [builtIn]) == .menuBar)
}

@Test func notchRectFromWidthsAndInset() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(NotchGeometry.notchRect(screenFrame: frame, leftWidth: 656, rightWidth: 656, topInset: 32) == notch)
    let offset = CGRect(x: -1512, y: 300, width: 1512, height: 982)
    #expect(
        NotchGeometry.notchRect(screenFrame: offset, leftWidth: 656, rightWidth: 656, topInset: 32)
            == CGRect(x: -856, y: 1250, width: 200, height: 32))
    #expect(NotchGeometry.notchRect(screenFrame: frame, leftWidth: 656, rightWidth: 656, topInset: 0) == nil)
    #expect(NotchGeometry.notchRect(screenFrame: frame, leftWidth: 0, rightWidth: 656, topInset: 32) == nil)
    #expect(NotchGeometry.notchRect(screenFrame: frame, leftWidth: 656, rightWidth: 0, topInset: 32) == nil)
}

@Test func panelHangsFromTopCenteredOnNotch() {
    let size = CGSize(width: 420, height: 132)
    let frame = NotchGeometry.panelFrame(notch: notch, screenFrame: builtIn.frame, size: size)
    #expect(frame == CGRect(x: 546, y: 850, width: 420, height: 132))
    #expect(NotchGeometry.idleFrame(notch: notch) == CGRect(x: 600, y: 950, width: 312, height: 32))
}

@Test func menuBarPanelStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let anchor = CGRect(x: 1480, y: 950, width: 24, height: 32)
    let frame = NotchGeometry.menuBarPanelFrame(
        anchor: anchor, visibleFrame: visible, size: CGSize(width: 420, height: 132))
    #expect(frame.maxX == 1504)  // 8 pt margin
    #expect(frame.maxY == 944)  // 6 pt under the menu bar item
}

private struct DecisionCase: Sendable {
    let prompt: Bool
    let notice: Bool
    let notched: Bool
    let count: Int
    let hovering: Bool
    var error = false
    let expected: PanelContent
}

@Test(arguments: [
    DecisionCase(prompt: true, notice: false, notched: false, count: 0, hovering: false, expected: .prompt),
    DecisionCase(prompt: false, notice: true, notched: false, count: 0, hovering: false, expected: .notice),
    DecisionCase(prompt: false, notice: false, notched: true, count: 3, hovering: false, expected: .idle),
    DecisionCase(prompt: false, notice: false, notched: true, count: 3, hovering: true, expected: .idleExpanded),
    DecisionCase(prompt: false, notice: false, notched: true, count: 0, hovering: false, expected: .hidden),
    // menu bar target has no idle panel
    DecisionCase(prompt: false, notice: false, notched: false, count: 3, hovering: false, expected: .hidden),
    // an error never hides the file the user is deciding about, the notice or the open list
    DecisionCase(prompt: true, notice: true, notched: true, count: 3, hovering: false, error: true, expected: .prompt),
    DecisionCase(
        prompt: false, notice: true, notched: false, count: 0, hovering: false, error: true, expected: .notice),
    DecisionCase(
        prompt: false, notice: false, notched: true, count: 3, hovering: true, error: true, expected: .idleExpanded),
    DecisionCase(prompt: false, notice: false, notched: true, count: 3, hovering: false, error: true, expected: .error),
    DecisionCase(
        prompt: false, notice: false, notched: false, count: 0, hovering: false, error: true, expected: .error),
])
private func reviewFocusPanelDecision(_ testCase: DecisionCase) {
    let target: PresentationTarget = testCase.notched ? .notch(builtIn) : .menuBar
    #expect(
        PanelDecision.content(
            promptAvailable: testCase.prompt, noticeVisible: testCase.notice, errorVisible: testCase.error,
            target: target,
            scheduledCount: testCase.count, hovering: testCase.hovering) == testCase.expected)
}

@Test func notchShapeHasSquareTopAndRoundedBottom() {
    let rect = CGRect(x: 0, y: 0, width: 420, height: 132)
    let path = NotchShape(bottomRadius: 20).path(in: rect)
    #expect(path.boundingRect == rect)
    #expect(path.contains(CGPoint(x: 0.5, y: 0.5)))  // top-left corner is square
    #expect(!path.contains(CGPoint(x: 0.5, y: 131.5)))  // bottom-left corner is rounded away
}

@Test func hoverSurvivesOnlyWhileTheClosedNotchIsShown() {
    #expect(PanelDecision.keepsHover(showing: .idle))
    #expect(PanelDecision.keepsHover(showing: .idleExpanded))
    for content in [PanelContent.hidden, .prompt, .notice] {
        #expect(!PanelDecision.keepsHover(showing: content))
    }
}

@Test func showNeverSkipsWhileTheHideFadeIsRunning() {
    #expect(PanelDecision.showStep(isOnScreen: false, isFadingOut: false, frameChanged: false) == .fadeIn)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: true, frameChanged: false) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: true, frameChanged: true) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: false, frameChanged: true) == .restore)
    #expect(PanelDecision.showStep(isOnScreen: true, isFadingOut: false, frameChanged: false) == .none)
}

@Test func openNotchContentStartsBelowTheHardwareNotch() {
    for content in [PanelContent.prompt, .notice, .idleExpanded, .error] {
        #expect(PanelDecision.topInset(for: content, notchHeight: 32) == 32)
        #expect(PanelDecision.topInset(for: content, notchHeight: nil) == 0)  // menu bar panel
    }
    // The closed notch lays itself out around the cutout.
    #expect(PanelDecision.topInset(for: .idle, notchHeight: 32) == 0)
    #expect(PanelDecision.topInset(for: .hidden, notchHeight: 32) == 0)
}
