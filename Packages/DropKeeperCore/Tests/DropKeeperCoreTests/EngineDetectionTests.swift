import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineDetectionTests {
    @Test func newDownloadBecomesPendingWithXattrId() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("report.pdf")
        let files = try harness.files()
        #expect(files.count == 1)
        #expect(files[0].state == .pending)
        #expect(files[0].kind == .document)
        #expect(harness.fs.xattr(ItemActions.idAttribute, at: path) == files[0].id)
    }

    @Test func reviewFocusPartialDownloadRenamedCreatesExactlyOneRecord() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let partial = EngineHarness.downloads + "/Unconfirmed 42.crdownload"
        harness.fs.createFile(partial, size: 10, added: harness.time.now())
        await harness.event(partial, [.created, .isFile])
        for size in [20, 30, 40] as [Int64] {
            harness.fs.setSize(partial, size)
            await harness.event(partial, [.modified, .isFile])
            await harness.advance(1)
        }
        let final = EngineHarness.downloads + "/installer.zip"
        harness.fs.move(partial, final)
        await harness.event(partial, [.renamed, .isFile])
        await harness.event(final, [.renamed, .isFile])
        await harness.event(final, [.modified, .isFile])
        await harness.advance(1)
        await harness.event(final, [.xattrModified, .isFile])
        await harness.advance(1)
        let files = try harness.files()
        #expect(files.map(\.path) == [final])
        #expect(files[0].state == .pending)
    }

    @Test func reviewFocusPreexistingFilesAreNeverRecordedEvenWhenRenamed() async throws {
        let old = EngineHarness.downloads + "/old.pdf"
        let harness = try EngineHarness { fs in
            fs.createFile(old, added: TestTimeSource.base.addingTimeInterval(-86_400))
        }
        try await harness.startWithDownloads()
        let renamed = EngineHarness.downloads + "/old-renamed.pdf"
        harness.fs.move(old, renamed)
        await harness.event(old, [.renamed, .isFile])
        await harness.event(renamed, [.renamed, .isFile])
        await harness.advance(2)
        await harness.advance(10_000)
        #expect(try harness.files().isEmpty)
        #expect(harness.fs.exists(renamed))
    }

    @Test func eventsAtOrBeforeBaselineAreIgnored() async throws {
        let harness = try EngineHarness()
        let folder = try await harness.startWithDownloads()
        let path = EngineHarness.downloads + "/early.pdf"
        harness.fs.createFile(path, added: harness.time.now())
        await harness.engine.handle(events: [
            FolderEvent(path: path, flags: [.created, .isFile], id: folder.baselineEventId)
        ])
        await harness.advance(1)
        #expect(try harness.files().isEmpty)
    }

    @Test func filesInSubfoldersAndHiddenFilesAreIgnored() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        harness.fs.mkdir(EngineHarness.downloads + "/Existing")
        await harness.drop("inner.pdf", in: EngineHarness.downloads + "/Existing")
        await harness.drop(".hidden")
        #expect(try harness.files().isEmpty)
    }

    @Test func newFolderIsOneItem() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let dir = EngineHarness.downloads + "/Unzipped"
        harness.fs.mkdir(dir, added: harness.time.now())
        harness.fs.createFile(dir + "/a.txt", added: harness.time.now())
        await harness.event(dir, [.created, .isDirectory])
        await harness.event(dir + "/a.txt", [.created, .isFile])
        await harness.advance(1)
        #expect(try harness.files().map(\.path) == [dir])
    }

    @Test func scheduledFileIsTrashedAtExpiryAndNotified() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 1800)
        #expect(harness.fs.xattr(ItemActions.expiryAttribute, at: path) != nil)
        await harness.advance(1799)
        #expect(harness.fs.exists(path))
        await harness.advance(1)
        #expect(!harness.fs.exists(path))
        #expect(try harness.store.file(id: id)?.state == .trashed)
        let note = await harness.nextNotification { if case .trashed = $0 { true } else { false } }
        guard case .trashed(let files) = note else {
            Issue.record("expected trashed notification")
            return
        }
        #expect(files.map(\.id) == [id])
    }

    @Test func pendingFileGetsDefaultChoiceAfterGrace() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        await harness.advance(298)
        #expect(try harness.files()[0].state == .pending)
        await harness.advance(2)
        #expect(try harness.files()[0].state == .kept)
    }

    @Test func renamedScheduledFileIsStillTrashedAtNewPath() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try harness.files()[0].id], duration: 1800)
        harness.fs.mkdir(EngineHarness.downloads + "/sub")
        let moved = EngineHarness.downloads + "/sub/b.pdf"
        harness.fs.move(path, moved)
        await harness.event(path, [.renamed, .isFile])
        await harness.event(moved, [.renamed, .isFile])
        #expect(try harness.files()[0].path == moved)
        await harness.advance(1800)
        #expect(!harness.fs.exists(moved))
        #expect(harness.fs.trashedPaths == [moved])
    }

    @Test func movedOutOfWatchedFoldersBecomesKept() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try harness.files()[0].id], duration: 1800)
        let out = "/fake/Users/me/Documents/a.pdf"
        harness.fs.move(path, out)
        await harness.event(path, [.renamed, .isFile])
        #expect(try harness.files()[0].state == .kept)
        await harness.advance(3600)
        #expect(harness.fs.exists(out))
        #expect(harness.fs.xattr(ItemActions.expiryAttribute, at: out) == nil)
    }

    @Test func reviewFocusUserDeletedFileBecomesGoneWithoutFailure() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.schedule(ids: [id], duration: 60)
        harness.fs.delete(path)
        await harness.advance(60)
        #expect(try harness.store.file(id: id)?.state == .gone)
        #expect(harness.fs.trashedPaths.isEmpty)
    }

    @Test func reviewFocusOverdueOnStartIsTrashedOnlyIfStillInFolder() async throws {
        let store = try FileStore.inMemory()
        let first = try EngineHarness(store: store)
        try await first.startWithDownloads()
        let inside = await first.drop("inside.pdf")
        let outside = await first.drop("outside.pdf")
        let ids = try first.files().map(\.id)
        try await first.engine.schedule(ids: ids, duration: 60)
        await first.engine.stop()

        // App not running for an hour; one file was moved out meanwhile.
        let second = try EngineHarness(store: store) { fs in
            fs.createFile(inside, added: TestTimeSource.base)
            fs.createFile(outside, added: TestTimeSource.base)
        }
        // Recreate the xattr/inode state the first harness had: reuse the first fake's inodes.
        for var file in try store.files(in: [.scheduled]) {
            file.inode = second.fs.stat(file.path)!.inode
            try store.update(file)
        }
        let moved = "/fake/Users/me/Documents/outside.pdf"
        second.fs.move(outside, moved)
        second.time.advance(by: 3600)
        try await second.engine.start()
        #expect(!second.fs.exists(inside))
        #expect(second.fs.exists(moved))
        let states = Dictionary(
            uniqueKeysWithValues: try store.files(in: FileState.allCases).map { ($0.path, $0.state) })
        #expect(states[inside] == .trashed)
        #expect(states[moved] == .kept)
    }

    @Test func unavailableFolderPausesExpiry() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try harness.files()[0].id], duration: 60)
        harness.fs.deniedDirectories = [EngineHarness.downloads]
        await harness.engine.handleWake()
        await harness.advance(120)
        #expect(harness.fs.exists(path))
        #expect(await harness.engine.watchedFolders[0].status == .noAccess)
        harness.fs.deniedDirectories = []
        await harness.engine.handleWake()
        #expect(!harness.fs.exists(path))
    }
}
