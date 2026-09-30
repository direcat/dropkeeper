import Foundation
import Testing

@testable import DropKeeperCore

@Suite(.serialized) struct EngineEndToEndTests {
    @Test func realDownloadIsDetectedScheduledAndDeleted() async throws {
        let root = try TempDir()
        defer { root.cleanup() }
        let downloads = root.path + "/Downloads"
        try FileManager.default.createDirectory(atPath: downloads, withIntermediateDirectories: false)
        // Whole seconds: GRDB stores dates with millisecond precision, so a sub-millisecond start
        // would make a stored expiry land just after `now` once the clock advances by the duration.
        // The real clock (not the fixed test base) keeps the folder's added_at comparable to real file dates.
        let time = TestTimeSource(Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
        let opened = try FileStore.open(at: URL(fileURLWithPath: root.path + "/db/dropkeeper.sqlite"))
        let engine = DropKeeperEngine(
            environment: EngineEnvironment(
                store: opened.store, fs: LiveFileSystem(), time: time,
                makeEventSource: { paths, since in try FolderWatcher(paths: paths, since: since, latency: 0.1) },
                currentEventId: { FolderWatcher.currentEventId() },
                needsRecovery: false, recoveryFolderHints: [], automaticTimer: false))
        try await engine.start()
        do {
            try await exercise(engine: engine, store: opened.store, downloads: downloads, time: time)
        } catch {
            await engine.stop()
            throw error
        }
        await engine.stop()
    }

    private func exercise(engine: DropKeeperEngine, store: FileStore, downloads: String, time: TestTimeSource)
        async throws
    {
        _ = try await engine.addFolder(path: downloads)
        var settings = await engine.currentSettings
        settings.deleteMode = .permanent  // keep the user's Trash clean
        try await engine.updateSettings(settings)

        try await Task.sleep(for: .milliseconds(300))
        let partial = downloads + "/file.pdf.crdownload"
        FileManager.default.createFile(atPath: partial, contents: Data(repeating: 1, count: 1024))
        try FileManager.default.moveItem(atPath: partial, toPath: downloads + "/file.pdf")

        var pending: [TrackedFile] = []
        for _ in 0..<50 where pending.isEmpty {
            try await Task.sleep(for: .milliseconds(200))
            time.advance(by: 1)
            await engine.tick()
            pending = try store.files(in: [.pending])
        }
        #expect(pending.map(\.displayName) == ["file.pdf"])
        let file = try #require(pending.first)
        #expect(LiveFileSystem().readXattr(ItemActions.idAttribute, at: downloads + "/file.pdf") == file.id)

        try await engine.schedule(ids: [file.id], duration: 1800)
        time.advance(by: 1800)
        await engine.tick()
        #expect(!FileManager.default.fileExists(atPath: downloads + "/file.pdf"))
        #expect(try store.file(id: file.id)?.state == .trashed)
    }
}
