import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)  // Fri 2027-01-15 09:00 in Prague

private var prague: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}

@Test(arguments: [
    (1800.0, "30 min"), (5400, "90 min"), (3600, "1 h"), (7200, "2 h"),
    (86_400, "1 day"), (172_800, "2 days"), (864_000, "10 days"),
])
func shortDurations(seconds: TimeInterval, expected: String) {
    #expect(DurationLabel.short(seconds) == expected)
}

@Test func longDurations() {
    let locale = Locale(identifier: "en_US")
    #expect(DurationLabel.long(3600, locale: locale) == "1 hour")
    #expect(DurationLabel.long(864_000, locale: locale) == "10 days")
    #expect(DurationLabel.long(300, locale: locale) == "5 minutes")
}

@Test func deletionLabels() {
    #expect(TimeLabels.deletion(at: base.addingTimeInterval(3600), now: base, calendar: prague) == "Today 10:00")
    #expect(TimeLabels.deletion(at: base.addingTimeInterval(86_400), now: base, calendar: prague) == "Tomorrow 09:00")
    let later = TimeLabels.deletion(at: base.addingTimeInterval(864_000), now: base, calendar: prague)
    #expect(later.hasPrefix("Mon"))
    #expect(later.contains("25"))
    #expect(later.hasSuffix("09:00"))
}

@Test func deletionLabelsFollowTwelveHourClock() {
    var calendar = prague
    calendar.locale = Locale(identifier: "en_US")
    let text = TimeLabels.deletion(at: base.addingTimeInterval(7 * 3600 + 40 * 60), now: base, calendar: calendar)
        .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    #expect(text == "Today 4:40 PM")
}

@Test func remainingLabelsAroundTheHour() {
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(3540), now: base) == "in 59 min")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(3570), now: base) == "in 1 h")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(3600), now: base) == "in 1 h")
}

@Test func remainingLabels() {
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(30), now: base) == "in <1 min")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(42 * 60), now: base) == "in 42 min")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(3 * 3600), now: base) == "in 3 h")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(49 * 3600), now: base) == "in 2 days")
    #expect(TimeLabels.remaining(until: base.addingTimeInterval(-10), now: base) == "in <1 min")
}

@Test func countdownLabels() {
    #expect(TimeLabels.countdown(9) == "0:09")
    #expect(TimeLabels.countdown(10) == "0:10")
    #expect(TimeLabels.countdown(0) == "0:00")
}
