import DropKeeperCore
import Foundation

enum DurationLabel {
    /// Short label for a timeline stop: "30 min", "1 h", "1 day", "10 days".
    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 1440, minutes % 1440 == 0 {
            let days = minutes / 1440
            return String(localized: "\(days) days", comment: "Timeline stop in days, e.g. 1 day, 10 days")
        }
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return String(localized: "\(hours) h", comment: "Timeline stop in hours, e.g. 1 h")
        }
        return String(localized: "\(minutes) min", comment: "Timeline stop in minutes, e.g. 30 min")
    }

    /// Value label of the notification timeout slider: "5 s", "1 min", "Never".
    static func notificationTimeout(_ seconds: TimeInterval) -> String {
        if seconds == Settings.notificationTimeoutNever {
            return String(
                localized: "Never", comment: "Notification timeout: the prompt and reminder never hide by themselves")
        }
        if seconds < 60 {
            let value = Int(seconds)
            return String(localized: "\(value) s", comment: "Notification timeout in seconds, e.g. 30 s")
        }
        return short(seconds)
    }

    /// Time left until a deadline, rounded up to the minute and never below one: "5 min", "1 h".
    static func remaining(_ seconds: TimeInterval) -> String {
        short(max(1, (seconds / 60).rounded(.up)) * 60)
    }

    /// Spelled-out duration for VoiceOver and settings: "1 hour", "10 days".
    static func long(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: seconds) ?? short(seconds)
    }
}
