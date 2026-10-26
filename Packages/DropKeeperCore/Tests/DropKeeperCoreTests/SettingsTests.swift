import Foundation
import Testing

@testable import DropKeeperCore

@Test func defaultsMatchSpec() {
    let settings = Settings()
    #expect(settings.launchAtLogin)
    #expect(settings.promptPresentation == .menuBar)
    #expect(!settings.quietMode)
    #expect(settings.timelineStops == [1800, 3600, 86_400, 864_000])
    #expect(settings.gracePeriod == 300)
    #expect(settings.defaultChoice == .keep)
    #expect(settings.deleteMode == .trash)
    #expect(!settings.finderTagEnabled)
    #expect(settings.ignoredPatterns == IgnorePattern.defaults)
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

@Test func normalizesGraceAndDefaultChoiceAndPatterns() {
    var settings = Settings()
    settings.gracePeriod = 42
    settings.defaultChoice = .expireAfter(12_345)
    settings.ignoredPatterns = [".DMG", "pkg", "", "*.dmg"]
    let norm = settings.normalized()
    #expect(norm.gracePeriod == 300)
    #expect(norm.defaultChoice == .keep)  // not one of the timeline stops
    #expect(norm.ignoredPatterns == ["*.dmg", "*.pkg"])
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

@Test func newInstallGetsDefaultPatterns() { #expect(Settings().ignoredPatterns == IgnorePattern.defaults) }

@Test func legacyExtensionsMigrateOnce() throws {
    let json = #"{"ignoredExtensions":["dmg","zip"]}"#
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    #expect(decoded.ignoredPatterns == ["~$*", "#*#", "*~", "*.dmg", "*.zip"])
    var edited = decoded
    edited.ignoredPatterns.removeFirst()  // user removes "~$*"
    let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(edited))
    #expect(again.ignoredPatterns == ["#*#", "*~", "*.dmg", "*.zip"])
}

@Test func normalizedPatternsAreTrimmedAndDeduped() {
    var settings = Settings()
    settings.ignoredPatterns = ["ZIP", "*.zip", "", "~$*"]
    #expect(settings.normalized().ignoredPatterns == ["*.zip", "~$*"])
}

@Test func lastChosenResolution() {
    var settings = Settings()
    settings.defaultChoice = .lastChosen
    #expect(settings.resolve(lastChoice: nil) == .keep)
    #expect(settings.resolve(lastChoice: .expireAfter(3600)) == .expireAfter(3600))
    #expect(settings.resolve(lastChoice: .expireAfter(12_345)) == .keep)  // stop no longer on the timeline
    #expect(settings.resolve(lastChoice: .keep) == .keep)
}

@Test func fixedChoicesIgnoreTheLastChoice() {
    var settings = Settings()
    settings.defaultChoice = .keep
    #expect(settings.resolve(lastChoice: .expireAfter(3600)) == .keep)
    settings.defaultChoice = .expireAfter(86_400)
    #expect(settings.resolve(lastChoice: .keep) == .expireAfter(86_400))
}

@Test func lastChosenSurvivesNormalization() {
    var settings = Settings()
    settings.defaultChoice = .lastChosen
    #expect(settings.normalized().defaultChoice == .lastChosen)
}

@Test func defaultChoiceEncodingsStayCompatible() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Blobs written by 1.0 (synthesized Codable) must still decode and re-encode identically.
    let keepJSON = #"{"keep":{}}"#
    let expireJSON = #"{"expireAfter":{"_0":3600}}"#
    let lastJSON = #"{"lastChosen":{}}"#
    #expect(try JSONDecoder().decode(DefaultChoice.self, from: Data(keepJSON.utf8)) == .keep)
    #expect(try JSONDecoder().decode(DefaultChoice.self, from: Data(expireJSON.utf8)) == .expireAfter(3600))
    #expect(try JSONDecoder().decode(DefaultChoice.self, from: Data(lastJSON.utf8)) == .lastChosen)
    #expect(String(bytes: try encoder.encode(DefaultChoice.keep), encoding: .utf8) == keepJSON)
    #expect(String(bytes: try encoder.encode(DefaultChoice.expireAfter(3600)), encoding: .utf8) == expireJSON)
    #expect(String(bytes: try encoder.encode(DefaultChoice.lastChosen), encoding: .utf8) == lastJSON)
}

@Test func reminderDefaults() throws {
    let settings = Settings()
    #expect(settings.reminderEnabled)
    #expect(settings.reminderLeadTime == 300)
    // A 1.0 blob has neither key.
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"quietMode":true}"#.utf8))
    #expect(decoded.reminderEnabled)
    #expect(decoded.reminderLeadTime == 300)
}

@Test func reminderLeadTimeNormalizes() {
    var settings = Settings()
    settings.reminderLeadTime = 42
    #expect(settings.normalized().reminderLeadTime == 300)
    settings.reminderLeadTime = 900
    #expect(settings.normalized().reminderLeadTime == 900)
}

@Test func defaultRulesShipDisabled() {
    let rules = Settings().rules
    #expect(
        rules.map(\.name) == [
            "Installers", "Screenshots on Desktop", "Images", "Archives", "Invitations & contacts",
        ])
    #expect(rules.allSatisfy { !$0.isEnabled })
    #expect(rules.map(\.duration) == [86_400, 86_400, 3600, 86_400, 1800])
    #expect(rules[1].folderPath == NSHomeDirectory() + "/Desktop")
    #expect(Set(rules.map(\.id)).count == 5)
    #expect(
        rules.map(\.match) == [
            .category(.installers), .category(.screenshots), .category(.images), .category(.archives),
            .category(.invitationsAndContacts),
        ])
}

@Test func legacyBlobGetsDefaultRulesAndDuplicateDetection() throws {
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"quietMode":true}"#.utf8))
    #expect(decoded.quietMode)
    #expect(decoded.rules == Settings().rules)
    #expect(decoded.duplicateDetection)
}

@Test func rulesRoundTripAndNormalize() throws {
    var settings = Settings()
    settings.rules = [
        Rule(name: "Calendar", match: .pattern(" ICS "), duration: 10),
        Rule(name: "Long", match: .category(.images), duration: 1e9),
    ]
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.rules == settings.rules)
    let normalized = settings.normalized().rules
    #expect(normalized[0].match == .pattern("*.ics"))
    #expect(normalized[0].duration == Settings.minStop)
    #expect(normalized[1].duration == Settings.maxStop)
}

@Test func undecodableRuleIsSkippedWithoutResettingOtherSettings() throws {
    let rule = Rule(name: "Images", match: .category(.images), duration: 3600)
    let good = try #require(String(bytes: try JSONEncoder().encode(rule), encoding: .utf8))
    let unknown =
        #"{"id":"6F1D0A10-0009-4C5E-9A10-D40F7E000009","name":"New","#
        + #""match":{"category":{"_0":"hologram"}},"duration":60,"isEnabled":true}"#
    let blob = #"{"quietMode":true,"rules":[\#(good),\#(unknown)]}"#
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(blob.utf8))
    #expect(decoded.quietMode)
    #expect(decoded.rules == [rule])
}

@Test func unreadableRulesKeyFallsBackToDefaultsOnly() throws {
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"quietMode":true,"rules":"oops"}"#.utf8))
    #expect(decoded.quietMode)
    #expect(decoded.rules == Settings().rules)
}
