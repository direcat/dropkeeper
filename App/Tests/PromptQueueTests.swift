import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func pending(_ id: String, seen offset: TimeInterval = 0) -> TrackedFile {
    TrackedFile(
        id: id, folderId: 1, path: "/tmp/\(id)", inode: 1, volumeId: "V", displayName: id, kind: .other,
        sizeBytes: 1, state: .pending, firstSeen: base.addingTimeInterval(offset), expiresAt: nil,
        trashPath: nil, failureCount: 0, updatedAt: base)
}

@Test func reviewFocusSeveralDownloadsFormOneStableStack() {
    var queue = PromptQueue()
    queue.update(pending: [pending("a")])
    #expect(queue.current?.id == "a")
    queue.update(pending: [pending("a"), pending("b", seen: 1), pending("c", seen: 2)])
    #expect(queue.current?.id == "a")  // the visible file does not jump
    #expect(queue.items.map(\.id) == ["a", "b", "c"])
    #expect(queue.targets(applyToAll: true) == ["a", "b", "c"])
    #expect(queue.targets(applyToAll: false) == ["a"])
}

@Test func reviewFocusDismissedFileIsNotPromptedAgain() {
    var queue = PromptQueue()
    queue.update(pending: [pending("a"), pending("b", seen: 1)])
    queue.dismiss(applyToAll: false)
    #expect(queue.current?.id == "b")
    queue.update(pending: [pending("a"), pending("b", seen: 1), pending("c", seen: 2)])
    #expect(queue.items.map(\.id) == ["b", "c"])
    queue.dismiss(applyToAll: true)
    #expect(queue.current == nil)
    queue.update(pending: [pending("a"), pending("b", seen: 1), pending("c", seen: 2), pending("d", seen: 3)])
    #expect(queue.items.map(\.id) == ["d"])
}

@Test func dismissalsAreForgottenOnceNoLongerPending() {
    var queue = PromptQueue()
    queue.update(pending: [pending("a")])
    queue.dismiss(applyToAll: false)
    queue.update(pending: [])
    queue.update(pending: [pending("a")])  // e.g. same id pending again after a restore
    #expect(queue.current?.id == "a")
}

@Test func decidedFilesLeaveTheQueue() {
    var queue = PromptQueue()
    queue.update(pending: [pending("a"), pending("b", seen: 1)])
    queue.update(pending: [pending("b", seen: 1)])
    #expect(queue.current?.id == "b")
}

@Test func dismissingDecidedIdsMovesToTheNextFile() {
    var queue = PromptQueue()
    queue.update(pending: [pending("a"), pending("b", seen: 1)])
    queue.dismiss(ids: ["a"])
    #expect(queue.current?.id == "b")
    queue.update(pending: [pending("b", seen: 1)])
    #expect(queue.items.map(\.id) == ["b"])
}
