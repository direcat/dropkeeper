import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct StatisticsTests {
    @Test func emptyStoreIsZero() throws {
        #expect(try FileStore.inMemory().statistics() == .zero)
    }

    @Test func countsDecisionsAndBytes() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf", size: 100)
        await harness.drop("b.pdf", size: 300)
        await harness.drop("c.pdf", size: 10)
        try await harness.engine.schedule(
            ids: [try harness.file(named: "a.pdf").id, try harness.file(named: "b.pdf").id], duration: 60)
        try await harness.engine.keep(ids: [try harness.file(named: "c.pdf").id])
        await harness.advance(60)
        var settings = await harness.engine.currentSettings
        settings.deleteMode = .permanent
        try await harness.engine.updateSettings(settings)
        await harness.drop("d.pdf", size: 50)
        try await harness.engine.deleteNow(ids: [try harness.file(named: "d.pdf").id])

        let stats = try await harness.engine.statistics()
        #expect(stats.movedToTrash == 2 && stats.deletedPermanently == 1 && stats.kept == 1)
        #expect(stats.handled == 4)
        #expect(stats.bytesFreed == 450)
    }

    @Test func bookkeepingNotCounted() async throws {
        let harness = try EngineHarness()
        let folder = try await harness.startWithDownloads()
        for name in ["a.pdf", "b.pdf", "c.pdf"] { await harness.drop(name) }
        try await harness.engine.removeFolder(id: try #require(folder.id))
        #expect(try await harness.engine.statistics().kept == 0)
    }

    @Test func rulesAndDuplicates() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.rules = [
            Rule(name: "DMGs", match: .pattern("*.dmg"), folderPath: EngineHarness.downloads, duration: 3600)
        ]
        settings.duplicateDetection = true
        try await harness.engine.updateSettings(settings)
        await harness.drop("x.dmg")

        let content = Data("same bytes".utf8)
        harness.fs.createFile(
            EngineHarness.downloads + "/orig.pdf", content: content, added: Date(timeIntervalSince1970: 0))
        let copy = EngineHarness.downloads + "/y.pdf"
        harness.fs.createFile(copy, content: content, added: harness.time.now())
        await harness.event(copy, [.created, .isFile])
        harness.time.advance(by: 1)
        await harness.engine.tick()
        await harness.settleDuplicateChecks()
        try await harness.engine.deleteNow(ids: [try harness.file(named: "y.pdf").id])

        let expired = TrackedFile(
            id: "dup-expired", folderId: nil, path: "/fake/z.pdf", inode: 9, volumeId: "V", displayName: "z.pdf",
            kind: .document, sizeBytes: 5, state: .trashed, firstSeen: .now, expiresAt: nil, trashPath: "/t/z.pdf",
            failureCount: 0, updatedAt: .now, duplicateOf: "orig.pdf", resolution: .expired)
        try harness.store.insert(expired)

        let stats = try await harness.engine.statistics()
        #expect(stats.scheduledByRules == 1 && stats.duplicatesDeleted == 2)
    }

    @Test func clearHistoryResetsStatistics() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.keep(ids: [try harness.file(named: "a.pdf").id])
        #expect(try await harness.engine.statistics().handled == 1)
        _ = try await harness.engine.clearHistory()
        #expect(try await harness.engine.statistics().handled == 0)
    }
}
