import AppKit
import DropKeeperCore
import SwiftUI
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func render(_ view: some View) -> CGImage? {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.proposedSize = ProposedViewSize(width: 420, height: nil)
    return renderer.cgImage
}

@MainActor
@Test func promptRendersAtDesignWidth() throws {
    let file = scheduledFile(expiresIn: 0, id: "Quarterly report final v2.pdf")
    let view = PromptView(
        file: file, stackCount: 3, duplicateOf: nil,
        timeline: .constant(TimelineModel(durations: Settings().timelineStops, preselect: .keep)),
        applyToAll: .constant(false), now: base, onDone: {}, onKeep: {}, onClose: {}, onOpen: {},
        onDeleteDuplicate: {})
    let image = try #require(render(view))
    #expect(image.width >= 420)
}

@MainActor
@Test func promptWithDuplicateRendersTheHint() throws {
    let file = scheduledFile(expiresIn: 0, id: "report (1).pdf")
    let make = { (duplicateOf: String?) in
        PromptView(
            file: file, stackCount: 1, duplicateOf: duplicateOf,
            timeline: .constant(TimelineModel(durations: Settings().timelineStops, preselect: .keep)),
            applyToAll: .constant(false), now: base, onDone: {}, onKeep: {}, onClose: {}, onOpen: {},
            onDeleteDuplicate: {})
    }
    let plain = try #require(render(make(nil)))
    let flagged = try #require(render(make("report.pdf")))
    #expect(flagged.height > plain.height)  // the hint and the Delete duplicate button add a row
}

@MainActor
@Test func noticeAndIdleRender() {
    #expect(render(NoticeView(files: [scheduledFile(expiresIn: 0, id: "a.pdf")], canUndo: true, onUndo: {})) != nil)
    #expect(render(NotchIdleView(count: 3, urgentSeconds: nil, notchWidth: 200)) != nil)
    #expect(render(NotchIdleView(count: 1, urgentSeconds: 7, notchWidth: 200)) != nil)
}

@Test func reviewFocusNoticeTitleMergesFiles() {
    #expect(NoticeView.title(for: [scheduledFile(expiresIn: 0, id: "a.pdf")]) == "a.pdf")
    let three = ["a", "b", "c"].map { scheduledFile(expiresIn: 0, id: $0) }
    #expect(NoticeView.title(for: three) == "3 files")
}

@Test func timelineHighlightsOnlyStopsUpToASelectedDuration() {
    var model = TimelineModel(durations: [1800, 3600, 86_400], preselect: .expireAfter(3600))
    #expect((0..<4).map(model.isHighlighted) == [true, true, false, false])
    model.select(3)
    #expect((0..<4).map(model.isHighlighted) == [false, false, false, true])
}

@Test func timelineLabelCentersOverDotUnlessItWouldOverflow() {
    // Short label near the right edge stays centered over the dot.
    #expect(ClampedCenterLayout.clampedCenter(368, labelWidth: 30, width: 388) == 368)
    // Wide label is shifted inward just enough to fit.
    #expect(ClampedCenterLayout.clampedCenter(368, labelWidth: 130, width: 388) == 323)
    #expect(ClampedCenterLayout.clampedCenter(20, labelWidth: 100, width: 388) == 50)
    // Wider than the track: centered in it.
    #expect(ClampedCenterLayout.clampedCenter(20, labelWidth: 400, width: 388) == 194)
}

@Test func idleAccessibilityValueAnnouncesCountdown() {
    #expect(NotchIdleView.accessibilityValue(urgentSeconds: 7) == "Deleting in 0:07")
    #expect(NotchIdleView.accessibilityValue(urgentSeconds: nil) == nil)
}

@MainActor
@Test(arguments: SettingsTab.allCases) func settingsTabRendersAtWindowSize(tab: SettingsTab) throws {
    let model = AppModel(applyLoginItem: { _ in })
    let view = SettingsTabView(tab: tab, model: model, store: SettingsDraft(model: model))
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(TK.Size.settingsWindow)
    let image = try #require(renderer.cgImage)
    #expect(CGFloat(image.width) >= TK.Size.settingsWindow.width)
    #expect(CGFloat(image.height) >= TK.Size.settingsWindow.height)
}

/// The spike: AppKit's toolbar tabs in this app's plain window give one toolbar item per tab, each with its symbol.
@MainActor
@Test func settingsWindowHasToolbarTabs() throws {
    let suite = "DropKeeperAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(3, forKey: SettingsTabViewController.selectedTabKey)
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    let controller = SettingsTabViewController(model: model, store: SettingsDraft(model: model), defaults: defaults)
    let window = NSWindow(contentViewController: controller)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    #expect(controller.tabStyle == .toolbar)
    #expect(controller.tabViewItems.count == SettingsTab.allCases.count)
    #expect(controller.tabViewItems.allSatisfy { $0.image != nil })
    #expect(controller.selectedTabViewItemIndex == 3)
    #expect(window.toolbar?.items.count == SettingsTab.allCases.count)
    controller.selectedTabViewItemIndex = 5
    #expect(defaults.integer(forKey: SettingsTabViewController.selectedTabKey) == 5)
}
