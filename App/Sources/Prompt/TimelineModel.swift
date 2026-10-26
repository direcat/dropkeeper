import DropKeeperCore
import Foundation

/// The prompt's timeline: duration stops followed by Keep.
struct TimelineModel: Equatable {
    enum Stop: Equatable {
        case duration(TimeInterval)
        case keep
    }

    let stops: [Stop]
    private(set) var selectedIndex: Int

    /// `preselect` is what the grace period would apply; a duration that is not a stop falls back to Keep.
    init(durations: [TimeInterval], preselect: ResolvedChoice) {
        stops = durations.map(Stop.duration) + [.keep]
        if case .expireAfter(let duration) = preselect, let index = durations.firstIndex(of: duration) {
            selectedIndex = index
        } else {
            selectedIndex = durations.count
        }
    }

    var selected: Stop { stops[selectedIndex] }

    mutating func moveLeft() { selectedIndex = max(0, selectedIndex - 1) }
    mutating func moveRight() { selectedIndex = min(stops.count - 1, selectedIndex + 1) }

    mutating func select(_ index: Int) {
        guard stops.indices.contains(index) else { return }
        selectedIndex = index
    }

    func deletionDate(from now: Date) -> Date? {
        guard case .duration(let duration) = selected else { return nil }
        return now.addingTimeInterval(duration)
    }
}

extension TimelineModel {
    /// The stop a revisited rule timer maps to: the same duration, else the nearest longer one, else the longest.
    /// Never Keep, so Return on a "Change" prompt can't silently keep the file.
    static func nearestStop(atLeast duration: TimeInterval, in durations: [TimeInterval]) -> TimeInterval {
        durations.filter { $0 >= duration }.min() ?? durations.max() ?? duration
    }

    /// The prompt's primary button: what confirming the selected stop does.
    var confirmLabel: String {
        switch selected {
        case .duration(let seconds): String(localized: "Delete in \(DurationLabel.short(seconds))")
        case .keep: String(localized: "Keep")
        }
    }
}
