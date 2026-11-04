import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct ResolutionTests {
    private func onlyFile(_ harness: EngineHarness) throws -> TrackedFile {
        try #require(try harness.files().first)
    }

    @Test func userKeepIsUserKept() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.keep(ids: [try onlyFile(harness).id])
        let file = try onlyFile(harness)
        #expect(file.state == .kept && file.resolution == .userKept)
    }

    @Test func graceDefaultKeepIsDefaultKept() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        let grace = await harness.engine.currentSettings.gracePeriod
        await harness.advance(grace)
        let file = try onlyFile(harness)
        #expect(file.state == .kept && file.resolution == .defaultKept)
    }

    @Test func expiryIsExpired() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness).id], duration: 60)
        await harness.advance(60)
        let file = try onlyFile(harness)
        #expect(file.state == .trashed && file.resolution == .expired)
    }

    @Test func deleteNowIsDeletedNow() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.deleteNow(ids: [try onlyFile(harness).id])
        let file = try onlyFile(harness)
        #expect(file.state == .trashed && file.resolution == .deletedNow)
    }

    @Test func undoTrashIsRestored() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        let id = try onlyFile(harness).id
        try await harness.engine.schedule(ids: [id], duration: 60)
        await harness.advance(60)
        try await harness.engine.undoTrash(ids: [id])
        let file = try onlyFile(harness)
        #expect(file.state == .kept && file.resolution == .restored)
    }

    @Test func removeFolderIsFolderRemoved() async throws {
        let harness = try EngineHarness()
        let folder = try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        await harness.drop("b.pdf")
        try await harness.engine.removeFolder(id: try #require(folder.id))
        let kept = try harness.files([.kept])
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { $0.resolution == .folderRemoved })
    }

    @Test func movedOutIsMovedOut() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness).id], duration: 1800)
        harness.fs.move(path, "/fake/Users/me/Documents/a.pdf")
        await harness.event(path, [.renamed, .isFile])
        let file = try onlyFile(harness)
        #expect(file.state == .kept && file.resolution == .movedOut)
    }

    @Test func deletedOutsideIsRemovedOutside() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness).id], duration: 60)
        harness.fs.delete(path)
        await harness.advance(60)
        let file = try onlyFile(harness)
        #expect(file.state == .gone && file.resolution == .removedOutside)
    }

    @Test func finderPutBackIsReappeared() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness).id], duration: 60)
        await harness.advance(60)
        harness.fs.move(FakeFileSystem.trashDir + "/a.pdf", path)
        await harness.event(path, [.renamed, .isFile])
        let file = try onlyFile(harness)
        #expect(file.state == .kept && file.resolution == .reappeared)
    }

    @Test func ruleScheduledFileIsViaRule() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.rules = [
            Rule(name: "DMGs", match: .pattern("*.dmg"), folderPath: EngineHarness.downloads, duration: 3600)
        ]
        try await harness.engine.updateSettings(settings)
        await harness.drop("a.dmg")
        await harness.settleDuplicateChecks()
        let file = try onlyFile(harness)
        #expect(file.state == .scheduled && file.viaRule && file.resolution == nil)
    }

    @Test func manuallyScheduledFileIsNotViaRule() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        try await harness.engine.schedule(ids: [try onlyFile(harness).id], duration: 60)
        #expect(try onlyFile(harness).viaRule == false)
    }

    @Test func scheduleClearsResolution() {
        var file = TrackedFile(
            id: "x", folderId: nil, path: "/fake/a.pdf", inode: 1, volumeId: "V", displayName: "a.pdf",
            kind: .document, sizeBytes: 1, state: .kept, firstSeen: .now, expiresAt: nil, trashPath: nil,
            failureCount: 0, updatedAt: .now, resolution: .userKept)
        ItemActions(fs: FakeFileSystem()).schedule(&file, duration: 60, now: .now, tagEnabled: false)
        #expect(file.resolution == nil)
    }

    @Test func decisionSet() {
        #expect(Resolution.allCases.filter(\.isDecision) == [.userKept, .defaultKept, .restored, .expired, .deletedNow])
        #expect(Resolution.decisionValues == ["userKept", "defaultKept", "restored", "expired", "deletedNow"])
    }
}
