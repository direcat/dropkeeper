import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineActionsTests {
    @Test func undoRestoresTrashedFileAsKept() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        await harness.advance(60)
        #expect(!harness.fs.exists(path))
        try await harness.engine.undoTrash(ids: [id])
        #expect(harness.fs.exists(path))
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .kept)
        #expect(harness.fs.xattr(ItemActions.expiryAttribute, at: path) == nil)
        await harness.event(path, [.renamed, .isFile])  // the restore itself produces an event
        #expect(try harness.files().count == 1)
    }

    @Test func undoRemovesFinderTagFromRestoredFile() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.finderTagEnabled = true
        try await harness.engine.updateSettings(settings)
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        #expect(harness.fs.tags(at: path) == ["Temporary"])
        await harness.advance(60)
        #expect(!harness.fs.exists(path))
        try await harness.engine.undoTrash(ids: [id])
        #expect(harness.fs.exists(path))
        #expect(harness.fs.tags(at: path).isEmpty)
        #expect(harness.fs.xattr(ItemActions.expiryAttribute, at: path) == nil)
        #expect(harness.fs.xattr(ItemActions.idAttribute, at: path) == id)
    }

    @Test func retryAfterFailureTrashesNow() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        harness.fs.failingTrashCount = 4
        await harness.advance(60)
        await harness.advance(1)
        await harness.advance(5)
        await harness.advance(30)
        #expect(try harness.store.file(id: id)?.state == .failed)
        let note = await harness.nextNotification {
            if case .failed = $0 { true } else { false }
        }
        guard case .failed(let failed) = note else {
            Issue.record("expected failed")
            return
        }
        #expect(failed.id == id)
        try await harness.engine.retry(ids: [id])
        #expect(!harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .trashed)
    }

    @Test func deleteNowTrashesPendingFileAndNotifies() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.deleteNow(ids: [id])
        #expect(!harness.fs.exists(path))
        #expect(harness.fs.trashedPaths == [path])
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .trashed)
        #expect(file.trashPath != nil)
        let note = await harness.nextNotification {
            if case .trashed = $0 { true } else { false }
        }
        guard case .trashed(let files) = note else {
            Issue.record("expected trashed")
            return
        }
        #expect(files.map(\.id) == [id])
        try await harness.engine.undoTrash(ids: [id])
        #expect(harness.fs.exists(path))
    }

    @Test func deleteNowTrashesScheduledAndFailedFiles() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let scheduledPath = await harness.drop("a.pdf")
        let failedPath = await harness.drop("b.pdf")
        let ids = try harness.files().map(\.id)
        try await harness.engine.schedule(ids: [ids[0]], duration: 3600)
        var failed = try #require(try harness.store.file(id: ids[1]))
        failed.state = .failed
        failed.expiresAt = nil
        try harness.store.update(failed)
        try await harness.engine.deleteNow(ids: ids)
        #expect(!harness.fs.exists(scheduledPath))
        #expect(!harness.fs.exists(failedPath))
        #expect(try harness.files([.trashed]).count == 2)
    }

    @Test func deleteNowRemovesPermanentlyInPermanentMode() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.deleteMode = .permanent
        try await harness.engine.updateSettings(settings)
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.deleteNow(ids: [id])
        #expect(!harness.fs.exists(path))
        #expect(harness.fs.removedPaths == [path])
        #expect(harness.fs.trashedPaths.isEmpty)
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .trashed)
        #expect(file.trashPath == nil)
        let note = await harness.nextNotification {
            if case .trashed = $0 { true } else { false }
        }
        guard case .trashed(let files) = note else {
            Issue.record("expected trashed")
            return
        }
        #expect(files.map(\.id) == [id])
    }

    @Test func deleteNowOnMissingFileMarksItGoneWithoutNotice() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        harness.fs.delete(path)
        try await harness.engine.deleteNow(ids: [id])
        #expect(try harness.store.file(id: id)?.state == .gone)
        #expect(harness.fs.trashedPaths.isEmpty)
        let note = await harness.nextNotification(timeout: .milliseconds(200)) {
            if case .trashed = $0 { true } else { false }
        }
        #expect(note == nil)
    }

    @Test func deleteNowReportsFailureAndLeavesRecordUntouched() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        harness.fs.failingTrashCount = 1
        await #expect(throws: EngineError.partialFailure(failedIds: [id])) {
            try await harness.engine.deleteNow(ids: [id])
        }
        #expect(harness.fs.exists(path))
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .pending)
        #expect(file.failureCount == 0)
    }

    @Test func deleteNowDoesNotTrashAFileThatReplacedTheFailedOne() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        var failed = try #require(try harness.store.file(id: id))
        failed.state = .failed
        failed.expiresAt = nil
        try harness.store.update(failed)
        harness.fs.delete(path)
        harness.fs.createFile(path, added: harness.time.now())  // a different file at the same path
        try await harness.engine.deleteNow(ids: [id])
        #expect(harness.fs.exists(path))
        #expect(harness.fs.trashedPaths.isEmpty)
        #expect(harness.fs.removedPaths.isEmpty)
        #expect(try harness.store.file(id: id)?.state == .gone)
    }

    @Test func deleteNowSkipsFilesOfAnUnavailableFolder() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        harness.fs.deniedDirectories = [EngineHarness.downloads]
        await harness.engine.handleWake()
        await #expect(throws: EngineError.partialFailure(failedIds: [id])) {
            try await harness.engine.deleteNow(ids: [id])
        }
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .pending)
    }

    @Test func deleteNowKeepsFailedRecordFailedWhenDisposalFails() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        var failed = try #require(try harness.store.file(id: id))
        failed.state = .failed
        failed.expiresAt = nil
        failed.failureCount = 4
        try harness.store.update(failed)
        harness.fs.failingTrashCount = 1
        await #expect(throws: EngineError.partialFailure(failedIds: [id])) {
            try await harness.engine.deleteNow(ids: [id])
        }
        #expect(harness.fs.exists(path))
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .failed)
        #expect(file.failureCount == 4)
    }

    @Test func deleteNowIgnoresKeptFiles() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.keep(ids: [id])
        try await harness.engine.deleteNow(ids: [id])
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .kept)
    }

    @Test func removingFolderKeepsItsActiveFiles() async throws {
        let harness = try EngineHarness()
        let folder = try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        try await harness.engine.removeFolder(id: try #require(folder.id))
        await harness.advance(120)
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .kept)
        #expect(await harness.engine.watchedFolders.isEmpty)
    }

    @Test func addingOverlappingFolderIsRejected() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        harness.fs.mkdir(EngineHarness.downloads + "/sub")
        await #expect(throws: EngineError.overlapsExistingFolder(EngineHarness.downloads + "/sub")) {
            try await harness.engine.addFolder(path: EngineHarness.downloads + "/sub")
        }
        await #expect(throws: EngineError.overlapsExistingFolder("/fake/Users/me")) {
            try await harness.engine.addFolder(path: "/fake/Users/me")
        }
        await #expect(throws: EngineError.notADirectory("/fake/nope")) {
            try await harness.engine.addFolder(path: "/fake/nope")
        }
    }

    @Test func secondWatchedFolderDetectsAndKeepsExpiryAcrossFolders() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        _ = try await harness.engine.addFolder(path: EngineHarness.desktop)
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        let moved = EngineHarness.desktop + "/a.pdf"
        harness.fs.move(path, moved)
        await harness.event(moved, [.renamed, .isFile])
        await harness.advance(60)
        #expect(harness.fs.trashedPaths == [moved])
    }

    @Test func enablingFinderTagTagsScheduledFiles() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try harness.files()[0].id], duration: 600)
        var settings = await harness.engine.currentSettings
        settings.finderTagEnabled = true
        try await harness.engine.updateSettings(settings)
        #expect(harness.fs.tags(at: path) == ["Temporary"])
        settings.finderTagEnabled = false
        try await harness.engine.updateSettings(settings)
        #expect(harness.fs.tags(at: path).isEmpty)
        #expect(try harness.store.settings().finderTagEnabled == false)
    }

    @Test func defaultChoiceDurationSchedulesAfterGrace() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.defaultChoice = .expireAfter(3600)
        try await harness.engine.updateSettings(settings)
        await harness.drop("a.pdf")
        await harness.advance(300)
        let file = try harness.files()[0]
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == harness.time.now().addingTimeInterval(3600))
    }

    @Test func ignoredPatternsAreSkipped() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.ignoredPatterns = [".DMG"]
        try await harness.engine.updateSettings(settings)
        await harness.drop("Installer.dmg")
        #expect(try harness.files().isEmpty)
    }

    @Test func clearHistoryKeepsActive() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        await harness.drop("b.pdf")
        let ids = try harness.files().map(\.id)
        try await harness.engine.keep(ids: [ids[0]])
        #expect(try await harness.engine.clearHistory() == 1)
        #expect(try harness.files().map(\.id) == [ids[1]])
    }

    @Test func recoveryRebuildsFromXattrsAndHints() async throws {
        let path = EngineHarness.downloads + "/survivor.pdf"
        let expiry = TestTimeSource.base.addingTimeInterval(3600)
        let harness = try EngineHarness(needsRecovery: true, hints: [EngineHarness.downloads]) { fs in
            fs.createFile(path, added: TestTimeSource.base)
            try? fs.writeXattr(ItemActions.idAttribute, value: "SURVIVOR", at: path)
            try? fs.writeXattr(ItemActions.expiryAttribute, value: ISODate.format(expiry), at: path)
        }
        try await harness.engine.start()
        #expect(await harness.engine.watchedFolders.map(\.path) == [EngineHarness.downloads])
        let file = try #require(try harness.store.file(id: "SURVIVOR"))
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == expiry)
        await harness.advance(3600)
        #expect(!harness.fs.exists(path))
    }

    @Test func fallbackScanPicksUpItemsAddedSincePreviousHeartbeat() async throws {
        let store = try FileStore.inMemory()
        let first = try EngineHarness(store: store)
        try await first.startWithDownloads()
        await first.engine.stop()  // heartbeat = base

        let newPath = EngineHarness.downloads + "/while-away.pdf"
        let oldPath = EngineHarness.downloads + "/before.pdf"
        let second = try EngineHarness(store: store) { fs in
            fs.createFile(oldPath, added: TestTimeSource.base.addingTimeInterval(-60))
            fs.createFile(newPath, added: TestTimeSource.base.addingTimeInterval(600))
        }
        second.time.advance(by: 1200)
        try await second.engine.start()
        await second.engine.handle(events: [
            FolderEvent(path: EngineHarness.downloads, flags: [.mustScanSubDirs], id: 0)
        ])
        await second.advance(1)
        #expect(try store.files(in: FileState.allCases).map(\.path) == [newPath])
    }

    @Test func wakeDoesNothingAfterStop() async throws {
        let harness = try EngineHarness()
        let (path, id) = try await scheduledThenStopped(harness)
        await harness.engine.handleWake()
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .scheduled)
    }

    @Test func clockChangeDoesNothingAfterStop() async throws {
        let harness = try EngineHarness()
        let (path, id) = try await scheduledThenStopped(harness)
        await harness.engine.handleClockChange()
        #expect(harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .scheduled)
    }

    /// A scheduled item whose expiry has passed after the engine was stopped.
    private func scheduledThenStopped(_ harness: EngineHarness) async throws -> (String, FileID) {
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        await harness.engine.stop()
        harness.time.advance(by: 120)
        return (path, id)
    }
}
