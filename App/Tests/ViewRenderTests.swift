import AppKit
import DropKeeperCore
import SwiftUI
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func render(_ view: some View) -> CGImage? {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.proposedSize = ProposedViewSize(width: TK.Size.panelWidth, height: nil)
    return renderer.cgImage
}

@MainActor
@Test func promptRendersAtDesignWidth() throws {
    let file = scheduledFile(expiresIn: 0, id: "Quarterly report final v2.pdf")
    let view = PromptView(
        file: file, stackCount: 3, duplicateOf: nil,
        timeline: .constant(TimelineModel(durations: Settings().timelineStops, preselect: .keep)),
        applyToAll: .constant(false), now: base, hideProgress: nil, hideSeconds: nil,
        onDone: {}, onKeep: {}, onClose: {}, onOpen: {}, onDeleteDuplicate: {})
    let image = try #require(render(view))
    #expect(image.width >= Int(TK.Size.panelWidth))
}

@MainActor
@Test func promptWithDuplicateRendersTheHint() throws {
    let file = scheduledFile(expiresIn: 0, id: "report (1).pdf")
    let make = { (duplicateOf: String?) in
        PromptView(
            file: file, stackCount: 1, duplicateOf: duplicateOf,
            timeline: .constant(TimelineModel(durations: Settings().timelineStops, preselect: .keep)),
            applyToAll: .constant(false), now: base, hideProgress: nil, hideSeconds: nil,
            onDone: {}, onKeep: {}, onClose: {}, onOpen: {}, onDeleteDuplicate: {})
    }
    let plain = try #require(render(make(nil)))
    let flagged = try #require(render(make("report.pdf")))
    #expect(flagged.height > plain.height)  // the hint and the Delete duplicate button add a row
}

@MainActor
private func prompt(hideProgress: Double?, hideSeconds: Int?) -> PromptView {
    PromptView(
        file: scheduledFile(expiresIn: 0, id: "report.pdf"), stackCount: 1, duplicateOf: nil,
        timeline: .constant(TimelineModel(durations: Settings().timelineStops, preselect: .keep)),
        applyToAll: .constant(false), now: base, hideProgress: hideProgress, hideSeconds: hideSeconds,
        onDone: {}, onKeep: {}, onClose: {}, onOpen: {}, onDeleteDuplicate: {})
}

@MainActor
@Test func promptRendersHideBarOnlyWithProgress() throws {
    let with = try #require(render(prompt(hideProgress: 0.5, hideSeconds: 15)))
    let without = try #require(render(prompt(hideProgress: nil, hideSeconds: nil)))
    #expect(with.height > without.height)  // the bar and the caption add a row
    let barOnly = try #require(render(prompt(hideProgress: 0.5, hideSeconds: nil)))
    #expect(barOnly.height > without.height)  // the bar alone is enough
    let captionOnly = try #require(render(prompt(hideProgress: nil, hideSeconds: 15)))
    #expect(captionOnly.height == without.height)  // seconds alone draw nothing
    #expect(PromptView.hideCaption(seconds: 15) == "Hides in 15 s · stays in the list")
    #expect(PromptView.hideCaption(seconds: nil) == nil)
}

@MainActor
@Test func promptMetadataIsSizeAndFolderName() {
    let file = scheduledFile(expiresIn: 0, id: "report.pdf")  // path /tmp/report.pdf, 1 byte
    #expect(PromptView.metadata(for: file) == "\(ByteCountFormatter.string(fromByteCount: 1, countStyle: .file)) · tmp")
    var rootFile = file
    rootFile.path = "/report.pdf"
    #expect(PromptView.metadata(for: rootFile).hasSuffix(FileManager.default.displayName(atPath: "/")))
}

@MainActor
@Test func noticeRenders() {
    #expect(render(NoticeView(files: [scheduledFile(expiresIn: 0, id: "a.pdf")], canUndo: true, onUndo: {})) != nil)
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

/// The window opens at its fixed size and centered on its screen, on first open and again after a close.
@MainActor
@Test func settingsWindowOpensCentered() throws {
    let suite = "DropKeeperAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    let controller = SettingsWindowController(model: model, defaults: defaults)

    func expectCentered() throws {
        let window = try #require(controller.settingsWindow)
        let visible = try #require(window.screen?.visibleFrame)
        let content = window.contentRect(forFrameRect: window.frame).size
        #expect(abs(content.width - TK.Size.settingsWindow.width) <= 1)
        #expect(abs(content.height - TK.Size.settingsWindow.height) <= 1)
        #expect(abs(window.frame.midX - visible.midX) <= 1)
        // AppKit's `center()` sits slightly above the true middle, so vertically only require it within the screen.
        #expect(visible.contains(window.frame) && window.frame.midY >= visible.midY - 1)
    }

    controller.show()
    try expectCentered()
    controller.settingsWindow?.close()
    controller.show()
    try expectCentered()
    #expect(controller.settingsWindow?.toolbar?.items.count == 6)
    controller.settingsWindow?.close()
}
