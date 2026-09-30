import Foundation
import Testing

@testable import DropKeeperCore

@Test func readyAfterSizeStableForInterval() {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/a.zip", size: 10, added: nil)
    var tracker = StabilityTracker()
    let start = TestTimeSource.base
    tracker.observe("/fake/D/a.zip", size: 10, now: start)
    #expect(tracker.poll(now: start.addingTimeInterval(0.5), fs: fs).isEmpty)
    let ready = tracker.poll(now: start.addingTimeInterval(1), fs: fs)
    #expect(ready.map(\.path) == ["/fake/D/a.zip"])
    #expect(tracker.isEmpty)
}

@Test func growingFileIsNotReadyUntilItStopsGrowing() {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/big.zip", size: 10, added: nil)
    var tracker = StabilityTracker()
    let start = TestTimeSource.base
    tracker.observe("/fake/D/big.zip", size: 10, now: start)
    for step in 1...120 {  // grows for two minutes: never dropped, never ready
        fs.setSize("/fake/D/big.zip", Int64(10 + step))
        #expect(tracker.poll(now: start.addingTimeInterval(Double(step)), fs: fs).isEmpty)
    }
    #expect(tracker.poll(now: start.addingTimeInterval(121), fs: fs).map(\.path) == ["/fake/D/big.zip"])
}

@Test func vanishedPathIsDropped() {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/x.crdownload", size: 10, added: nil)
    var tracker = StabilityTracker()
    tracker.observe("/fake/D/x.crdownload", size: 10, now: TestTimeSource.base)
    fs.delete("/fake/D/x.crdownload")
    #expect(tracker.poll(now: TestTimeSource.base.addingTimeInterval(5), fs: fs).isEmpty)
    #expect(tracker.isEmpty)
}

@Test func reObservingDoesNotResetTimerWhenSizeUnchanged() {
    let fs = FakeFileSystem()
    fs.mkdir("/fake/D")
    fs.createFile("/fake/D/a.pdf", size: 10, added: nil)
    var tracker = StabilityTracker()
    let start = TestTimeSource.base
    tracker.observe("/fake/D/a.pdf", size: 10, now: start)
    tracker.observe("/fake/D/a.pdf", size: 10, now: start.addingTimeInterval(0.9))
    #expect(tracker.poll(now: start.addingTimeInterval(1), fs: fs).count == 1)
}
