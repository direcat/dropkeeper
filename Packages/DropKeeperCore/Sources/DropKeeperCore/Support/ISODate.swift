import Foundation

public enum ISODate {
    public static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    public static func parse(_ string: String) -> Date? {
        try? Date.ISO8601FormatStyle().parse(string)
    }
}
