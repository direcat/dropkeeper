import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

@Test func presetsAreSortedWithinSettingsRange() {
    #expect(StopPresets.all == StopPresets.all.sorted())
    #expect(StopPresets.all.first! >= Settings.minStop)
    #expect(StopPresets.all.last! <= Settings.maxStop)
    #expect(StopPresets.next(after: [1800, 3600]) == 10_800)
    #expect(StopPresets.next(after: [StopPresets.all.last!]) == nil)
}

@Test func defaultChoiceTagsRoundTrip() {
    let stops: [TimeInterval] = [1800, 3600, 86_400]
    #expect(DefaultChoiceTag.tag(for: .keep, stops: stops) == -1)
    #expect(DefaultChoiceTag.tag(for: .expireAfter(3600), stops: stops) == 1)
    #expect(DefaultChoiceTag.tag(for: .expireAfter(999), stops: stops) == -1)
    #expect(DefaultChoiceTag.choice(for: 2, stops: stops) == .expireAfter(86_400))
    #expect(DefaultChoiceTag.choice(for: -1, stops: stops) == .keep)
    #expect(DefaultChoiceTag.choice(for: 9, stops: stops) == .keep)
}

/// The Settings draft converges only because a second normalization changes nothing.
@Test func normalizedSettingsAreStable() {
    var unsorted = Settings()
    unsorted.timelineStops = [86_400, 1800, 1800, 10, 99_999_999, 3600, 604_800]
    unsorted.defaultChoice = .expireAfter(10)
    unsorted.ignoredPatterns = [".DMG", "dmg", " zip", ""]
    unsorted.gracePeriod = 42
    var tooFew = Settings()
    tooFew.timelineStops = [3600, 3600]
    for input in [unsorted, tooFew, Settings()] {
        #expect(input.normalized().normalized() == input.normalized())
    }
}

@Test func stopPickerOffersOnlyUnusedPresets() {
    let stops: [TimeInterval] = [1800, 3600, 86_400]
    let options = StopPresets.options(for: 1, in: stops)
    #expect(options.contains(3600))
    #expect(!options.contains(1800))
    #expect(!options.contains(86_400))
    #expect(options == options.sorted())
    #expect(options.count == StopPresets.all.count - 2)
    // An out-of-range index offers every preset not used by the stops.
    #expect(StopPresets.options(for: 9, in: stops).count == StopPresets.all.count - 3)
}

@Test func stopToAddPrefersLargerThenFillsGaps() {
    #expect(StopPresets.stopToAdd(to: [1800, 3600]) == 10_800)
    #expect(StopPresets.stopToAdd(to: [1800, 7_776_000]) == 2_592_000)
    #expect(StopPresets.stopToAdd(to: StopPresets.all) == nil)
}

@Test func stepSliderSnapsUnknownValue() {
    let options = Settings.gracePeriodOptions
    #expect(StepSlider.index(of: 900, in: options) == 2)
    #expect(StepSlider.index(of: 1000, in: options) == 2)
    #expect(StepSlider.index(of: 1, in: options) == 0)
    #expect(StepSlider.index(of: 99_999, in: options) == options.count - 1)
    // Non-numeric values have no distance: they fall back to the first.
    #expect(StepSlider.index(of: "x", in: ["a", "b"]) == 0)
    #expect(StepSlider.index(of: HistoryRetention.oneYear, in: HistoryRetention.allCases) == 3)
}

@Test func tabsInSpecOrder() {
    #expect(SettingsTab.allCases.map(\.rawValue) == ["general", "folders", "expiry", "rules", "data", "about"])
    #expect(
        SettingsTab.allCases.map(\.systemImage)
            == ["gearshape", "folder", "timer", "list.bullet.rectangle", "externaldrive", "info.circle"])
}

@Test func defaultChoiceTagRoundTripsLastChosen() {
    let stops: [TimeInterval] = [1800, 3600]
    #expect(DefaultChoiceTag.tag(for: .lastChosen, stops: stops) == -2)
    #expect(DefaultChoiceTag.choice(for: -2, stops: stops) == .lastChosen)
    #expect(DefaultChoiceTag.choice(for: -1, stops: stops) == .keep)
    #expect(DefaultChoiceTag.choice(for: 1, stops: stops) == .expireAfter(3600))
}

@Test func ruleSummaryText() {
    let category = Rule(name: "Installers", match: .category(.installers), duration: 86_400)
    let text = RuleSummary.text(for: category)
    #expect(text.hasPrefix("\(RuleSummary.categoryName(.installers)) · "))
    #expect(text.hasSuffix(" · \(DurationLabel.long(86_400))"))
    let pattern = Rule(
        name: "Invoices", match: .pattern("invoice*.pdf"), folderPath: "/Users/me/Desktop", duration: 3600)
    #expect(RuleSummary.text(for: pattern) == "invoice*.pdf · Desktop · \(DurationLabel.long(3600))")
}

private func watched(_ id: Int64, _ path: String) -> WatchedFolder {
    WatchedFolder(
        id: id, path: path, bookmark: nil, volumeId: "v", addedAt: Date(timeIntervalSince1970: 0), baselineEventId: 0,
        status: .ok)
}

@Test func desktopRuleIsInertWhenDesktopNotWatched() {
    let desktop = Rule(
        name: "Screenshots", match: .category(.screenshots), folderPath: "/Users/me/Desktop", duration: 3600)
    let everywhere = Rule(name: "Images", match: .category(.images), duration: 3600)
    let downloads = watched(1, "/Users/me/Downloads")
    let watchedDesktop = watched(2, "/Users/me/Desktop")
    #expect(RuleSummary.isInert(desktop, watched: [downloads]))
    #expect(!RuleSummary.isInert(desktop, watched: [downloads, watchedDesktop]))
    #expect(!RuleSummary.isInert(everywhere, watched: []))
}

@Test(arguments: ["*", "**", "?*", "*?*", "?"])
func wildcardOnlyPatternsMatchEverything(raw: String) {
    #expect(PatternCheck.matchesEverything(raw))
}

@Test(arguments: ["zip", ".DMG", "~$*", "*.zip", "invoice?.pdf", "", "  "])
func ordinaryPatternsAreNotMatchAll(raw: String) {
    #expect(!PatternCheck.matchesEverything(raw))
}

@Test func ruleOrderMovesAndClamps() {
    let rules = (1...3).map { Rule(name: "r\($0)", match: .category(.images), duration: 60) }
    #expect(RuleOrder.move(rules, id: rules[0].id, by: 1).map(\.name) == ["r2", "r1", "r3"])
    #expect(RuleOrder.move(rules, id: rules[2].id, by: -1).map(\.name) == ["r1", "r3", "r2"])
    #expect(RuleOrder.move(rules, id: rules[0].id, by: -1) == rules)
    #expect(RuleOrder.move(rules, id: rules[2].id, by: 1) == rules)
    #expect(RuleOrder.move(rules, id: UUID(), by: 1) == rules)
}

@Test func defaultRuleNamesAreLocalizedUntilRenamed() {
    let installers = Rule.defaults(home: "/h")[0]
    #expect(RuleSummary.displayName(for: installers) == RuleSummary.categoryName(.installers))
    var renamed = installers
    renamed.name = "My installers"
    #expect(RuleSummary.displayName(for: renamed) == "My installers")
    let custom = Rule(name: "Installers", match: .category(.installers), duration: 60)
    #expect(RuleSummary.displayName(for: custom) == "Installers")
    let desktop = Rule.defaults(home: "/h")[1]
    #expect(RuleSummary.displayName(for: desktop) == String(localized: "Screenshots on Desktop"))
}
