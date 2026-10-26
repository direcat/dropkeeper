import Foundation

public enum PromptPresentation: String, Codable, Sendable, CaseIterable {
    case automatic, menuBar, notch
}

public enum DefaultChoice: Codable, Sendable, Equatable {
    case keep
    case expireAfter(TimeInterval)
}

public enum DeleteMode: String, Codable, Sendable, CaseIterable {
    case trash, permanent
}

public enum HistoryRetention: String, Codable, Sendable, CaseIterable {
    case oneMonth, threeMonths, sixMonths, oneYear, twoYears, forever

    public var interval: TimeInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .oneMonth: return 30 * day
        case .threeMonths: return 90 * day
        case .sixMonths: return 182 * day
        case .oneYear: return 365 * day
        case .twoYears: return 730 * day
        case .forever: return nil
        }
    }
}

public struct Settings: Codable, Sendable, Equatable {
    public static let minStop: TimeInterval = 300
    public static let maxStop: TimeInterval = 90 * 86_400
    public static let gracePeriodOptions: [TimeInterval] = [60, 300, 900, 3600]

    public var launchAtLogin = true
    public var promptPresentation = PromptPresentation.menuBar
    public var quietMode = false
    public var timelineStops: [TimeInterval] = [1800, 3600, 86_400, 864_000]
    public var gracePeriod: TimeInterval = 300
    public var defaultChoice = DefaultChoice.keep
    public var deleteMode = DeleteMode.trash
    public var finderTagEnabled = false
    public var ignoredPatterns = IgnorePattern.defaults
    public var historyRetention = HistoryRetention.oneYear

    public init() {}

    enum CodingKeys: String, CodingKey {
        case launchAtLogin, promptPresentation, quietMode, timelineStops, gracePeriod, defaultChoice,
            deleteMode, finderTagEnabled, ignoredPatterns, historyRetention
    }

    /// Pre-1.1 key, decode-only: migrated into `ignoredPatterns` when that key is absent.
    private enum LegacyKeys: String, CodingKey {
        case ignoredExtensions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        promptPresentation =
            try container.decodeIfPresent(PromptPresentation.self, forKey: .promptPresentation)
            ?? defaults.promptPresentation
        quietMode = try container.decodeIfPresent(Bool.self, forKey: .quietMode) ?? defaults.quietMode
        timelineStops =
            try container.decodeIfPresent([TimeInterval].self, forKey: .timelineStops) ?? defaults.timelineStops
        gracePeriod = try container.decodeIfPresent(TimeInterval.self, forKey: .gracePeriod) ?? defaults.gracePeriod
        defaultChoice =
            try container.decodeIfPresent(DefaultChoice.self, forKey: .defaultChoice) ?? defaults.defaultChoice
        deleteMode = try container.decodeIfPresent(DeleteMode.self, forKey: .deleteMode) ?? defaults.deleteMode
        finderTagEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .finderTagEnabled) ?? defaults.finderTagEnabled
        if let patterns = try container.decodeIfPresent([String].self, forKey: .ignoredPatterns) {
            ignoredPatterns = patterns
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let extensions = try legacy.decodeIfPresent([String].self, forKey: .ignoredExtensions) ?? []
            ignoredPatterns = defaults.ignoredPatterns + extensions.map { "*.\($0)" }
        }
        historyRetention =
            try container.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention) ?? defaults.historyRetention
    }

    /// Returns a copy with every value inside its allowed range.
    public func normalized() -> Settings {
        var result = self
        var stops = Array(Set(timelineStops.map { min(max($0, Self.minStop), Self.maxStop) })).sorted()
        if stops.count < 2 { stops = Settings().timelineStops }
        result.timelineStops = Array(stops.prefix(5))
        if !Self.gracePeriodOptions.contains(gracePeriod) { result.gracePeriod = 300 }
        if case .expireAfter(let duration) = defaultChoice, !result.timelineStops.contains(duration) {
            result.defaultChoice = .keep
        }
        var seen = Set<String>()
        result.ignoredPatterns =
            ignoredPatterns
            .compactMap(IgnorePattern.normalize)
            .filter { seen.insert($0).inserted }
        return result
    }
}
