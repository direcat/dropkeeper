import Foundation

enum TimeLabels {
    /// Exact deletion time: "Today 16:40", "Tomorrow 09:15", "Tue 2 Oct 09:15" (locale-dependent).
    static func deletion(at date: Date, now: Date, calendar: Calendar = .current) -> String {
        let locale = calendar.locale ?? .current
        let time = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .hour(uses12HourClock(locale) ? .defaultDigits(amPM: .abbreviated) : .twoDigits(amPM: .omitted))
                .minute(.twoDigits))
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today \(time)", comment: "Deletion time today, e.g. Today 16:40")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return String(localized: "Tomorrow \(time)", comment: "Deletion time tomorrow, e.g. Tomorrow 09:15")
        }
        let day = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day(.defaultDigits).month(.abbreviated))
        return "\(day) \(time)"
    }

    /// Time left, for list rows: "in 42 min", "in 3 h", "in 2 days".
    static func remaining(until date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 60 else { return String(localized: "in <1 min", comment: "Less than a minute left") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return String(localized: "in \(minutes) min", comment: "Minutes left, e.g. in 42 min") }
        let hours = max(1, Int(seconds / 3600))
        if hours < 48 { return String(localized: "in \(hours) h", comment: "Hours left, e.g. in 3 h") }
        let days = Int(seconds / 86_400)
        return String(localized: "in \(days) days", comment: "Days left, e.g. in 2 days")
    }

    private static func uses12HourClock(_ locale: Locale) -> Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? false
    }

    /// Last-seconds countdown: "0:09".
    static func countdown(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
