import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct StatisticsTests {
    private func id(_ harness: EngineHarness, _ name: String) throws -> String {
        try #require(try harness.files().first { $0.displayName == name }).id
    }

    @Test func emptyStoreIsZero() throws {
        #expect(try FileStore.inMemory().statistics() == .zero)
    }

    @Test func countsDecisionsAndBytes() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf", size: 100)
        await harness.drop("b.pdf", size: 300)
        await harness.drop("c.pdf", size: 10)
        try await harness.engine.schedule(ids: [try id(harness, "a.pdf"), try id(harness, "b.pdf")], duration: 60)
        try await harness.engine.keep(ids: [try id(harness, "c.pdf")])
        await harness.advance(60)
        var settings = await harness.engine.currentSettings
        settings.deleteMode = .permanent
        try await harness.engine.updateSettings(settings)
        await harness.drop("d.pdf", size: 50)
        try await harness.engine.deleteNow(ids: [try id(harness, "d.pdf")])

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
        try await harness.engine.deleteNow(ids: [try id(harness, "y.pdf")])

        let stats = try await harness.engine.statistics()
        #expect(stats.scheduledByRules == 1 && stats.duplicatesDeleted == 1)
    }

    @Test func clearHistoryResetsStatistics() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.keep(ids: [try id(harness, "a.pdf")])
        #expect(try await harness.engine.statistics().handled == 1)
        _ = try await harness.engine.clearHistory()
        #expect(try await harness.engine.statistics().handled == 0)
    }
}
