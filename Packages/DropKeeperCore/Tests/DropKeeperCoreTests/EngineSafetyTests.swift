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

    // MARK: Finding 3: batch actions do not stop at the first error

    @Test func undoOfSeveralItemsRestoresTheRestWhenOneFails() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let first = await harness.drop("a.pdf")
        let second = await harness.drop("b.pdf")
        let ids = try harness.files().map(\.id)
        try await harness.engine.schedule(ids: ids, duration: 60)
        await harness.advance(60)
        #expect(!harness.fs.exists(first))
        #expect(!harness.fs.exists(second))
        harness.fs.delete(FakeFileSystem.trashDir + "/a.pdf")  // emptied from the Trash meanwhile
        await #expect(throws: EngineError.partialFailure(failedIds: [ids[0]])) {
            try await harness.engine.undoTrash(ids: ids)
        }
        #expect(harness.fs.exists(second))
        #expect(try harness.store.file(id: ids[1])?.state == .kept)
        #expect(try harness.store.file(id: ids[0])?.state == .trashed)
    }

    // MARK: Minor findings

    @Test func recoveryKeepsEveryPathSharingAnIdAndNeverTrashesThem() async throws {
        let original = EngineHarness.downloads + "/original.pdf"
        let copy = EngineHarness.downloads + "/copy.pdf"
        let expiry = ISODate.format(TestTimeSource.base.addingTimeInterval(60))
        let harness = try EngineHarness(needsRecovery: true, hints: [EngineHarness.downloads]) { fs in
            for path in [original, copy] {
                fs.createFile(path, added: TestTimeSource.base)
                try? fs.writeXattr(ItemActions.idAttribute, value: "DUP", at: path)
                try? fs.writeXattr(ItemActions.expiryAttribute, value: expiry, at: path)
            }
        }
        try await harness.engine.start()
        let files = try harness.files()
        #expect(Set(files.map(\.path)) == [original, copy])
        #expect(files.allSatisfy { $0.state == .kept })
        for file in files {
            #expect(harness.fs.xattr(ItemActions.idAttribute, at: file.path) == file.id)
            #expect(harness.fs.xattr(ItemActions.expiryAttribute, at: file.path) == nil)
        }
        await harness.advance(120)
        #expect(harness.fs.exists(original))
        #expect(harness.fs.exists(copy))
    }

    @Test func downloadStabilizingAtQuitIsPromptedAfterStart() async throws {
        let store = try FileStore.inMemory()
        let first = try EngineHarness(store: store)
        try await first.startWithDownloads()
        await first.engine.stop()  // heartbeat = base

        let path = EngineHarness.downloads + "/late.pdf"
        let second = try EngineHarness(store: store) { fs in
            fs.createFile(path, added: TestTimeSource.base.addingTimeInterval(1))
        }
        second.time.advance(by: 30)
        try await second.engine.start()
        await second.advance(1)
        let files = try store.files(in: FileState.allCases)
        #expect(files.map(\.path) == [path])
        #expect(files.first?.state == .pending)
    }

    @Test func rootFolderIsRejected() async throws {
        let harness = try EngineHarness()
        harness.fs.mkdir("/")
        try await harness.engine.start()
        await #expect(throws: EngineError.invalidFolder("/")) {
            try await harness.engine.addFolder(path: "/")
        }
        #expect(await harness.engine.watchedFolders.isEmpty)
    }

    @Test func refreshFoldersPicksUpGrantedAccessAndProcessesOverdueItems() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try harness.files()[0].id], duration: 60)
        harness.fs.deniedDirectories = [EngineHarness.downloads]
        await harness.engine.refreshFolders()
        #expect(await harness.engine.watchedFolders[0].status == .noAccess)
        harness.time.advance(by: 120)
        harness.fs.deniedDirectories = []
        await harness.engine.refreshFolders()
        #expect(await harness.engine.watchedFolders[0].status == .ok)
        #expect(!harness.fs.exists(path))
    }
}
