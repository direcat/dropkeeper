import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct HistoryTests {
    private func onlyFile(_ harness: EngineHarness, _ name: String) throws -> TrackedFile {
        try #require(try harness.files().first { $0.displayName == name })
    }

    @Test func historyShowsDecisionsNewestFirstLimited() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        for index in 0..<12 {
            await harness.drop("f\(index).pdf")
            let id = try onlyFile(harness, "f\(index).pdf").id
            if index.isMultiple(of: 2) {
                try await harness.engine.keep(ids: [id])
            } else {
                try await harness.engine.deleteNow(ids: [id])
            }
            await harness.advance(1)
        }
        let history = try harness.store.history(limit: 10)
        #expect(history.count == 10)
        #expect(history.map(\.updatedAt) == history.map(\.updatedAt).sorted(by: >))
        #expect(history.first?.displayName == "f11.pdf")
    }

    @Test func historyHidesBookkeeping() async throws {
        let harness = try EngineHarness()
        let folder = try await harness.startWithDownloads()
        // userKept
        await harness.drop("kept.pdf")
        try await harness.engine.keep(ids: [try onlyFile(harness, "kept.pdf").id])
        // movedOut
        let moved = await harness.drop("moved.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness, "moved.pdf").id], duration: 1800)
        harness.fs.move(moved, "/fake/Users/me/Documents/moved.pdf")
        await harness.event(moved, [.renamed, .isFile])
        // removedOutside
        let removed = await harness.drop("removed.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness, "removed.pdf").id], duration: 60)
        harness.fs.delete(removed)
        await harness.advance(60)
        // reappeared
        let back = await harness.drop("back.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness, "back.pdf").id], duration: 60)
        await harness.advance(60)
        harness.fs.move(FakeFileSystem.trashDir + "/back.pdf", back)
        await harness.event(back, [.renamed, .isFile])
        // folderRemoved
        await harness.drop("folder.pdf")
        try await harness.engine.removeFolder(id: try #require(folder.id))

        let all = try harness.files()
        #expect(all.contains { $0.resolution == .movedOut })
        #expect(all.contains { $0.resolution == .removedOutside })
        #expect(all.contains { $0.resolution == .reappeared })
        #expect(all.contains { $0.resolution == .folderRemoved })
        #expect(try harness.store.history(limit: 10).map(\.resolution) == [.userKept])
    }

    @Test func historyIncludesUnknownResolution() throws {
        let store = try FileStore.inMemory()
        let file = TrackedFile(
            id: "x", folderId: nil, path: "/fake/a.pdf", inode: 1, volumeId: "V", displayName: "a.pdf",
            kind: .document, sizeBytes: 1, state: .kept, firstSeen: .now, expiresAt: nil, trashPath: nil,
            failureCount: 0, updatedAt: .now, resolution: nil)
        try store.insert(file)
        #expect(try store.history(limit: 10).count == 1)
    }

    @Test func historyOutcomeDistinguishesPermanentDelete() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.deleteMode = .permanent
        try await harness.engine.updateSettings(settings)
        await harness.drop("a.pdf")
        try await harness.engine.deleteNow(ids: [try onlyFile(harness, "a.pdf").id])
        await harness.advance(1)
        settings.deleteMode = .trash
        try await harness.engine.updateSettings(settings)
        await harness.drop("b.pdf")
        try await harness.engine.deleteNow(ids: [try onlyFile(harness, "b.pdf").id])

        let outcomes = try harness.store.history(limit: 10).reversed().map(\.historyOutcome)
        #expect(outcomes == [.deletedPermanently, .movedToTrash(canPutBack: true)])
    }

    @Test func historyOutcomeForKeptAndActive() {
        var file = TrackedFile(
            id: "x", folderId: nil, path: "/fake/a.pdf", inode: 1, volumeId: "V", displayName: "a.pdf",
            kind: .document, sizeBytes: 1, state: .kept, firstSeen: .now, expiresAt: nil, trashPath: nil,
            failureCount: 0, updatedAt: .now)
        #expect(file.historyOutcome == .kept)
        file.state = .scheduled
        #expect(file.historyOutcome == nil)
    }

    @Test func historyExcludesActiveAndFailed() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("pending.pdf")
        await harness.drop("scheduled.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness, "scheduled.pdf").id], duration: 3600)
        var failed = try onlyFile(harness, "pending.pdf")
        failed.state = .failed
        try harness.store.update(failed)
        await harness.drop("pending2.pdf")
        #expect(try harness.store.history(limit: 10).isEmpty)
    }

    @Test func historyUpdatesStreamsDecisions() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        let stream = harness.engine.historyUpdates()
        try await harness.engine.keep(ids: [try onlyFile(harness, "a.pdf").id])
        for try await files in stream where !files.isEmpty {
            #expect(files.map(\.displayName) == ["a.pdf"])
            break
        }
    }
}
