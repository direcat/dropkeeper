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
    unsorted.ignoredExtensions = [".DMG", "dmg", " zip", ""]
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
