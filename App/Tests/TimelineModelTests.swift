import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let stops: [TimeInterval] = [1800, 3600, 86_400, 864_000]

@Test func preselectsWhatTheGracePeriodWouldApply() {
    #expect(TimelineModel(durations: stops, preselect: .keep).selected == .keep)
    #expect(TimelineModel(durations: stops, preselect: .expireAfter(86_400)).selected == .duration(86_400))
    #expect(TimelineModel(durations: stops, preselect: .expireAfter(999)).selected == .keep)
}

@Test func keepIsTheLastStop() {
    let model = TimelineModel(durations: stops, preselect: .keep)
    #expect(model.stops.count == 5)
    #expect(model.stops.last == .keep)
}

@Test func arrowsMoveAndClamp() {
    var model = TimelineModel(durations: stops, preselect: .expireAfter(3600))
    model.moveLeft()
    model.moveLeft()
    #expect(model.selectedIndex == 0)
    for _ in 0..<10 { model.moveRight() }
    #expect(model.selected == .keep)
    model.select(2)
    #expect(model.selected == .duration(86_400))
    model.select(42)
    #expect(model.selectedIndex == 2)
}

@Test func deletionDate() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var model = TimelineModel(durations: stops, preselect: .expireAfter(3600))
    #expect(model.deletionDate(from: now) == now.addingTimeInterval(3600))
    model.select(4)
    #expect(model.deletionDate(from: now) == nil)
}

@Test func confirmLabelFollowsTheSelectedStop() {
    var model = TimelineModel(durations: stops, preselect: .expireAfter(3600))
    #expect(model.confirmLabel == "Delete in 1 h")
    model.select(0)
    #expect(model.confirmLabel == "Delete in 30 min")
    model.select(4)
    #expect(model.confirmLabel == "Keep")
}
