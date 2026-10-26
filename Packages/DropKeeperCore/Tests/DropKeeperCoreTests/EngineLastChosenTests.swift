import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineLastChosenTests {
    private func lastChosenHarness() async throws -> EngineHarness {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.defaultChoice = .lastChosen
        try await harness.engine.updateSettings(settings)
        return harness
    }

    @Test func promptChoiceDrivesGraceAutoApply() async throws {
        let harness = try await lastChosenHarness()
        await harness.drop("a.pdf")
        let first = try harness.files()[0].id
        try await harness.engine.schedule(ids: [first], duration: 86_400, recordChoice: true)
        await harness.drop("b.pdf")
        let grace = await harness.engine.currentSettings.gracePeriod
        await harness.advance(grace + 1)
        let second = try #require(try harness.files().first { $0.id != first })
        #expect(second.state == .scheduled)
        // The engine schedules from the tick that applied the default.
        #expect(second.expiresAt == harness.time.now().addingTimeInterval(86_400))
    }

    @Test func listChangeDoesNotRecord() async throws {
        let harness = try await lastChosenHarness()
        await harness.drop("a.pdf")
        let first = try harness.files()[0].id
        try await harness.engine.schedule(ids: [first], duration: 86_400, recordChoice: false)
        #expect(await harness.engine.resolvedDefaultChoice == .keep)
    }

    @Test func keepRecordsWhenAsked() async throws {
        let harness = try await lastChosenHarness()
        await harness.drop("a.pdf")
        let first = try harness.files()[0].id
        try await harness.engine.schedule(ids: [first], duration: 3600, recordChoice: true)
        #expect(await harness.engine.resolvedDefaultChoice == .expireAfter(3600))
        await harness.drop("c.pdf")
        let third = try #require(try harness.files().first { $0.id != first })
        try await harness.engine.keep(ids: [third.id], recordChoice: true)
        #expect(await harness.engine.resolvedDefaultChoice == .keep)
    }

    @Test func removedStopFallsBackToKeep() async throws {
        let harness = try await lastChosenHarness()
        await harness.drop("a.pdf")
        let first = try harness.files()[0].id
        try await harness.engine.schedule(ids: [first], duration: 86_400, recordChoice: true)
        var settings = await harness.engine.currentSettings
        settings.timelineStops = [1800, 3600, 864_000]
        try await harness.engine.updateSettings(settings)
        await harness.drop("b.pdf")
        let grace = settings.gracePeriod
        await harness.advance(grace + 1)
        let second = try #require(try harness.files().first { $0.id != first })
        #expect(second.state == .kept)
    }
}
