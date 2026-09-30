import Foundation
import Testing

@testable import DropKeeperCore

@Test func defaultsMatchSpec() {
    let settings = Settings()
    #expect(settings.launchAtLogin)
    #expect(settings.promptPresentation == .automatic)
    #expect(!settings.quietMode)
    #expect(settings.timelineStops == [1800, 3600, 86_400, 864_000])
    #expect(settings.gracePeriod == 300)
    #expect(settings.defaultChoice == .keep)
    #expect(settings.deleteMode == .trash)
    #expect(!settings.finderTagEnabled)
    #expect(settings.ignoredExtensions.isEmpty)
    #expect(settings.historyRetention == .oneYear)
}

@Test func normalizesTimelineStops() {
    var settings = Settings()
    settings.timelineStops = [10, 3600, 3600, 999_999_999, 7200, 86_400, 172_800]
    let norm = settings.normalized()
    #expect(norm.timelineStops == [300, 3600, 7200, 86_400, 172_800])  // clamped, deduped, sorted, max 5
    settings.timelineStops = [3600]
    #expect(settings.normalized().timelineStops == Settings().timelineStops)  // fewer than 2 → defaults
}

@Test func normalizesGraceAndDefaultChoiceAndExtensions() {
    var settings = Settings()
    settings.gracePeriod = 42
    settings.defaultChoice = .expireAfter(12_345)
    settings.ignoredExtensions = [".DMG", "pkg", "", "dmg"]
    let norm = settings.normalized()
    #expect(norm.gracePeriod == 300)
    #expect(norm.defaultChoice == .keep)  // not one of the timeline stops
    #expect(norm.ignoredExtensions == ["dmg", "pkg"])
}

@Test func decodesMissingKeysWithDefaults() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"quietMode":true}"#.utf8))
    #expect(settings.quietMode)
    #expect(settings.gracePeriod == 300)
}

@Test func retentionIntervals() {
    #expect(HistoryRetention.oneMonth.interval == TimeInterval(30 * 86_400))
    #expect(HistoryRetention.oneYear.interval == TimeInterval(365 * 86_400))
    #expect(HistoryRetention.forever.interval == nil)
}

@Test func folderContainment() {
    let folder = WatchedFolder(
        id: 1, path: "/a/Downloads", bookmark: nil, volumeId: "V", addedAt: .now,
        baselineEventId: 0, status: .ok)
    #expect(folder.contains("/a/Downloads/x.pdf"))
    #expect(folder.contains("/a/Downloads/sub/x.pdf"))
    #expect(!folder.contains("/a/Downloads"))
    #expect(!folder.contains("/a/DownloadsOld/x.pdf"))
}

@Test func isoDateRoundTrip() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(ISODate.parse(ISODate.format(date)) == date)
    #expect(ISODate.parse("garbage") == nil)
}
