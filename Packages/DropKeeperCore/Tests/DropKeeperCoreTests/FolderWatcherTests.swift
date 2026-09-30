import Foundation
import Testing

@testable import DropKeeperCore

/// Waits for the first event matching `predicate`, or nil after `timeout`.
func firstEvent(
    in stream: AsyncStream<[FolderEvent]>, timeout: Duration = .seconds(5),
    where predicate: @escaping @Sendable (FolderEvent) -> Bool
) async -> FolderEvent? {
    await withTaskGroup(of: FolderEvent?.self) { group in
        group.addTask {
            for await batch in stream {
                if let match = batch.first(where: predicate) { return match }
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

@Suite(.serialized) struct FolderWatcherTests {
    @Test func reportsCreatedFile() async throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let watcher = try FolderWatcher(paths: [dir.path], since: nil, latency: 0.1)
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let path = dir.createFile("hello.txt")
        let event = await firstEvent(in: watcher.events) { $0.path == path && $0.flags.contains(.created) }
        #expect(event != nil)
        #expect(event?.flags.contains(.isFile) == true)
        #expect((event?.id ?? 0) > 0)
    }

    @Test func reportsRenameForBothPaths() async throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let old = dir.createFile("a.crdownload")
        let watcher = try FolderWatcher(paths: [dir.path], since: nil, latency: 0.1)
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let new = dir.path + "/a.pdf"
        try FileManager.default.moveItem(atPath: old, toPath: new)
        let event = await firstEvent(in: watcher.events) { $0.path == new && $0.flags.contains(.renamed) }
        #expect(event != nil)
    }

    @Test func replaysEventsSinceStoredId() async throws {
        let dir = try TempDir()
        defer { dir.cleanup() }
        let since = FolderWatcher.currentEventId()
        let path = dir.createFile("while-quit.txt")
        try await Task.sleep(for: .seconds(1))  // let fseventsd journal the event
        let watcher = try FolderWatcher(paths: [dir.path], since: since, latency: 0.1)
        defer { watcher.stop() }
        let event = await firstEvent(in: watcher.events, timeout: .seconds(10)) { $0.path == path }
        #expect(event != nil)
    }
}
