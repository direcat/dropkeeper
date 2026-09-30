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
        file: file, stackCount: 3,
        timeline: .constant(TimelineModel(durations: Settings().timelineStops, defaultChoice: .keep)),
        applyToAll: .constant(false), now: base, onDone: {}, onKeep: {}, onClose: {})
    let image = try #require(render(view))
    #expect(image.width >= 420)
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
    var model = TimelineModel(durations: [1800, 3600, 86_400], defaultChoice: .expireAfter(3600))
    #expect((0..<4).map(model.isHighlighted) == [true, true, false, false])
    model.select(3)
    #expect((0..<4).map(model.isHighlighted) == [false, false, false, true])
}
