import DropKeeperCore
import Foundation
import SwiftUI
import Testing

@testable import DropKeeper

private func file(_ id: String, state: FileState, expiresIn: TimeInterval = 0) -> TrackedFile {
    var file = scheduledFile(expiresIn: expiresIn, id: id)
    file.state = state
    if state != .scheduled { file.expiresAt = nil }
    return file
}

@Test func sectionsOrderAndOmitEmpty() {
    let waiting = file("p", state: .pending)
    let late = file("late", state: .scheduled, expiresIn: 600)
    let soon = file("soon", state: .scheduled, expiresIn: 60)
    let sections = ListSections.make(pending: [waiting], scheduled: [late, soon], failed: [])
    #expect(sections.map(\.0) == [.waiting, .deletingSoon])
    #expect(sections[1].1.map(\.id) == ["soon", "late"])
    let all = ListSections.make(pending: [waiting], scheduled: [late], failed: [file("f", state: .failed)])
    #expect(all.map(\.0) == [.waiting, .deletingSoon, .couldNotDelete])
    #expect(ListSections.make(pending: [], scheduled: [], failed: []).isEmpty)
}

@Test func listTabsAreUpcomingThenHistory() {
    #expect(ListTab.allCases == [.upcoming, .history])
}

@Test func absoluteDeletionTimeIsShortInTheListRows() {
    let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 09:00 in Prague
    #expect(TimeLabels.absolute(at: now.addingTimeInterval(3600), now: now, calendar: calendar) == "10:00")
    #expect(
        TimeLabels.absolute(at: now.addingTimeInterval(86_400), now: now, calendar: calendar) == "Tomorrow 09:00")
    let later = TimeLabels.absolute(at: now.addingTimeInterval(864_000), now: now, calendar: calendar)
    #expect(later.contains("25") && later.contains("Jan") && !later.contains(":"))
}

@MainActor
@Test func footerCaptionNamesTheSoonestDeletion() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(ListFooter.caption(scheduled: [], now: now) == "No files scheduled")
    let soon = file("soon", state: .scheduled, expiresIn: 360)
    let late = file("late", state: .scheduled, expiresIn: 7200)
    #expect(ListFooter.caption(scheduled: [late, soon], now: now) == "Next deletion in 6 min")
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

@Test func finderRevealPicksFileThenFolderThenNothing() {
    let path = "/Users/me/Downloads/report.pdf"
    #expect(FinderReveal.target(for: path, fileExists: { _ in true }) == .file(path))
    #expect(
        FinderReveal.target(for: path, fileExists: { $0 == "/Users/me/Downloads" }) == .folder("/Users/me/Downloads"))
    #expect(FinderReveal.target(for: path, fileExists: { _ in false }) == .unavailable)
}

@Test func statusAccessibilityValues() {
    #expect(StatusAccessibility.value(scheduledCount: 0, urgentSeconds: nil) == "No files scheduled")
    #expect(StatusAccessibility.value(scheduledCount: 1, urgentSeconds: nil) == "1 file scheduled")
    #expect(StatusAccessibility.value(scheduledCount: 3, urgentSeconds: nil) == "3 files scheduled")
    #expect(StatusAccessibility.value(scheduledCount: 3, urgentSeconds: 7) == "Deleting in 0:07")
}

@Test func countdownDotPulsesEverySecondAndStaysSolidWithReduceMotion() {
    let even = Date(timeIntervalSince1970: 1_000)
    let odd = Date(timeIntervalSince1970: 1_001.4)
    #expect(StatusPulse.dotAlpha(now: even, reduceMotion: false) == 1)
    #expect(StatusPulse.dotAlpha(now: odd, reduceMotion: false) == 0.3)
    #expect(StatusPulse.dotAlpha(now: even, reduceMotion: true) == 1)
    #expect(StatusPulse.dotAlpha(now: odd, reduceMotion: true) == 1)
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
    let view = PendingListView(model: model, actions: actions)
    #expect(ImageRenderer(content: view).cgImage != nil)
}
