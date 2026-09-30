import Foundation
import Testing

@testable import DropKeeperCore

/// Regression tests for the final whole-branch review: never trash what the user did not schedule,
/// never silently drop a schedule.
@Suite struct EngineSafetyTests {
    private func harnessWithDefault(_ choice: DefaultChoice, store: FileStore? = nil) async throws -> EngineHarness {
        let harness = try EngineHarness(store: store)
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.defaultChoice = choice
        try await harness.engine.updateSettings(settings)
        return harness
    }

    // MARK: Finding 1: purged history

    @Test func keptFileIsNotRedetectedAfterHistoryIsClearedAndItIsRenamed() async throws {
        let harness = try await harnessWithDefault(.expireAfter(1800))
        let path = await harness.drop("a.pdf")
        try await harness.engine.keep(ids: [try harness.files()[0].id])
        #expect(try await harness.engine.clearHistory() == 1)
        let renamed = EngineHarness.downloads + "/b.pdf"
        harness.fs.move(path, renamed)
        await harness.event(path, [.renamed, .isFile])
        await harness.event(renamed, [.renamed, .isFile])
        await harness.advance(1)
        await harness.advance(1801)
        await harness.advance(1801)
        #expect(harness.fs.exists(renamed))
        #expect(try harness.files([.pending, .scheduled]).isEmpty)
        #expect(harness.fs.trashedPaths.isEmpty)
    }

    @Test func keptFileIsNotRedetectedByRescanAfterHistoryIsCleared() async throws {
        // A previous session ended before this download, so the rescan bound alone would admit it.
        let store = try FileStore.inMemory()
        try store.setMeta(.lastHeartbeatAt, ISODate.format(TestTimeSource.base.addingTimeInterval(-600)))
        let harness = try await harnessWithDefault(.expireAfter(1800), store: store)
        let path = await harness.drop("a.pdf")
        try await harness.engine.keep(ids: [try harness.files()[0].id])
        _ = try await harness.engine.clearHistory()
        await harness.engine.handle(events: [
            FolderEvent(path: EngineHarness.downloads, flags: [.mustScanSubDirs], id: 0)
        ])
        await harness.advance(1)
        await harness.advance(1801)
        await harness.advance(1801)
        #expect(harness.fs.exists(path))
        #expect(try harness.files([.pending, .scheduled]).isEmpty)
    }

    @Test func keptFileIsNotRedetectedAfterRestartFollowingClearedHistory() async throws {
        let store = try FileStore.inMemory()
        var settings = Settings()
        settings.defaultChoice = .expireAfter(1800)
        try store.saveSettings(settings)
        let first = try EngineHarness(store: store)
        try await first.startWithDownloads()
        await first.drop("a.pdf")
        let id = try first.files()[0].id
        try await first.engine.keep(ids: [id])
        _ = try await first.engine.clearHistory()
        await first.engine.stop()

        let renamed = EngineHarness.downloads + "/b.pdf"
        let second = try EngineHarness(store: store) { fs in
            fs.createFile(renamed, added: TestTimeSource.base)
            try? fs.writeXattr(ItemActions.idAttribute, value: id, at: renamed)
        }
        second.time.advance(by: 60)
        try await second.engine.start()
        await second.event(renamed, [.renamed, .isFile])
        await second.advance(1)
        await second.advance(1801)
        await second.advance(1801)
        #expect(second.fs.exists(renamed))
        #expect(try store.files(in: [.pending, .scheduled]).isEmpty)
    }

    @Test func freshCopyOfPurgedFileIsStillANewItem() async throws {
        let harness = try await harnessWithDefault(.keep)
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.keep(ids: [id])
        _ = try await harness.engine.clearHistory()
        await harness.advance(60)
        let copy = EngineHarness.downloads + "/a copy.pdf"
        harness.fs.createFile(copy, added: harness.time.now())
        try harness.fs.writeXattr(ItemActions.idAttribute, value: id, at: copy)
        await harness.event(copy, [.created, .isFile])
        await harness.advance(1)
        let files = try harness.files()
        #expect(files.map(\.path) == [copy])
        #expect(files.first?.state == .pending)
        #expect(files.first?.id != id)
        #expect(harness.fs.exists(path))
    }

    // MARK: Finding 2: folder lost between status refreshes

    @Test func unmountBetweenRefreshesPausesExpiryAndRemountResumesIt() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        let offline = "/fake/offline-Downloads"
        harness.fs.move(EngineHarness.downloads, offline)  // volume unmounted, no wake, no event
        await harness.advance(120)
        #expect(try harness.store.file(id: id)?.state == .scheduled)
        #expect(await harness.engine.watchedFolders[0].status != .ok)
        harness.fs.move(offline, EngineHarness.downloads)
        await harness.advance(1)
        #expect(await harness.engine.watchedFolders[0].status == .ok)
        #expect(!harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .trashed)
    }

    @Test func accessRevokedBetweenRefreshesPausesExpiryAndRegrantResumesIt() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        harness.fs.deniedDirectories = [EngineHarness.downloads]
        await harness.advance(120)
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .scheduled)
        #expect(await harness.engine.watchedFolders[0].status == .noAccess)
        harness.fs.deniedDirectories = []
        await harness.advance(1)
        #expect(!harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .trashed)
    }

    @Test func deletionEventWhileFolderIsUnmountedDoesNotMarkGone() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 600)
        let offline = "/fake/offline-Downloads"
        harness.fs.move(EngineHarness.downloads, offline)
        await harness.event(path, [.removed, .isFile])
        #expect(try harness.store.file(id: id)?.state == .scheduled)
        harness.fs.move(offline, EngineHarness.downloads)
        await harness.advance(600)
        #expect(!harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .trashed)
    }
}
