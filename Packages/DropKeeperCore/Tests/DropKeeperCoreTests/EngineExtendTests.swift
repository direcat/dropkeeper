import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineExtendTests {
    @Test func extendAddsTheTimerLength() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        let path = await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        let start = harness.time.now()
        try await harness.engine.schedule(ids: [id], duration: 3600)
        await harness.advance(3300)
        try await harness.engine.extend(ids: [id])
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == start.addingTimeInterval(7200))
        #expect(file.scheduleDuration == 3600)
        let expiryMark = harness.fs.xattr(ItemActions.expiryAttribute, at: path)
        #expect(expiryMark == ISODate.format(start.addingTimeInterval(7200)))
        // The file survives its original expiry.
        await harness.advance(600)
        #expect(harness.fs.exists(path))
    }

    @Test func extendLegacyRecord() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        let start = harness.time.now()
        try await harness.engine.schedule(ids: [id], duration: 600)
        var legacy = try #require(try harness.store.file(id: id))
        legacy.scheduleDuration = nil
        try harness.store.update(legacy)
        try await harness.engine.extend(ids: [id])
        let file = try #require(try harness.store.file(id: id))
        #expect(file.expiresAt == start.addingTimeInterval(1200))
        #expect(file.scheduleDuration == 600)
    }

    @Test func extendIgnoresPending() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        await harness.drop("a.pdf")
        let id = try harness.files()[0].id
        try await harness.engine.extend(ids: [id])
        let file = try #require(try harness.store.file(id: id))
        #expect(file.state == .pending)
        #expect(file.expiresAt == nil)
    }
}
