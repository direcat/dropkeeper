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

    init(durations: [TimeInterval], defaultChoice: DefaultChoice) {
        stops = durations.map(Stop.duration) + [.keep]
        if case .expireAfter(let duration) = defaultChoice, let index = durations.firstIndex(of: duration) {
            selectedIndex = index
        } else {
            selectedIndex = min(1, max(0, durations.count - 1))
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
