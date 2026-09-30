import Foundation
import Synchronization

@testable import DropKeeperCore

final class TestTimeSource: TimeSource {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let current: Mutex<Date>

    init(_ start: Date = TestTimeSource.base) { current = Mutex(start) }

    func now() -> Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    func set(_ date: Date) { current.withLock { $0 = date } }
}
