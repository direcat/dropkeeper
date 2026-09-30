import Foundation
import Testing

@testable import DropKeeperCore

private let baseTime = TestTimeSource.base

private func file(_ state: FileState, expiresIn: TimeInterval? = nil, firstSeen: Date = baseTime) -> TrackedFile {
    TrackedFile(
        id: UUID().uuidString, folderId: 1, path: "/fake/D/x", inode: 1, volumeId: "V", displayName: "x",
        kind: .other, sizeBytes: 1, state: state, firstSeen: firstSeen,
        expiresAt: expiresIn.map { baseTime.addingTimeInterval($0) }, trashPath: nil, failureCount: 0,
        updatedAt: baseTime)
}

@Test func deadlines() {
    let settings = Settings()
    #expect(Scheduler.deadline(for: file(.pending), settings: settings) == baseTime.addingTimeInterval(300))
    let scheduledFile = file(.scheduled, expiresIn: 60)
    #expect(Scheduler.deadline(for: scheduledFile, settings: settings) == baseTime.addingTimeInterval(60))
    for state in [FileState.kept, .trashed, .gone, .failed] {
        #expect(Scheduler.deadline(for: file(state, expiresIn: 60), settings: settings) == nil)
    }
}

@Test func nextDeadlineIsEarliest() {
    let files = [file(.scheduled, expiresIn: 600), file(.pending), file(.scheduled, expiresIn: 30), file(.kept)]
    #expect(Scheduler.nextDeadline(in: files, settings: Settings()) == baseTime.addingTimeInterval(30))
    #expect(Scheduler.nextDeadline(in: [file(.kept)], settings: Settings()) == nil)
}
