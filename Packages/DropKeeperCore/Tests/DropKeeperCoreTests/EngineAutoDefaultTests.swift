import Foundation
import Testing

@testable import DropKeeperCore

@Suite(.serialized) struct EngineAutoDefaultTests {
    private func harness(
        quiet: Bool = true, auto: Bool = true, choice: DefaultChoice = .keep, rules: [Rule]? = nil
    ) async throws -> EngineHarness {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.quietMode = quiet
        settings.autoApplyDefault = auto
        settings.defaultChoice = choice
        if let rules { settings.rules = rules }
        try await harness.engine.updateSettings(settings)
        return harness
    }

    @Test func optionOnKeepsAtOnceLikeTheGracePeriod() async throws {
        let harness = try await harness()
        await harness.drop("a.pdf")
        let file = try harness.file(named: "a.pdf")
        #expect(file.state == .kept && file.resolution == .defaultKept)
    }

    @Test func optionOnSchedulesAtOnceWithTheDefaultDuration() async throws {
        let harness = try await harness(choice: .expireAfter(3600))
        await harness.drop("a.pdf")
        let file = try harness.file(named: "a.pdf")
        #expect(file.state == .scheduled && file.scheduleDuration == 3600 && !file.viaRule)
    }

    @Test func optionOffLeavesTheFilePending() async throws {
        let harness = try await harness(auto: false)
        await harness.drop("a.pdf")
        #expect(try harness.file(named: "a.pdf").state == .pending)
    }

    @Test func quietModeOffIgnoresTheOption() async throws {
        let harness = try await harness(quiet: false)
        await harness.drop("a.pdf")
        #expect(try harness.file(named: "a.pdf").state == .pending)
    }

    @Test func rulesStillWin() async throws {
        let rule = Rule(
            name: "Images", match: .category(.images), folderPath: EngineHarness.downloads, duration: 7200)
        let harness = try await harness(choice: .expireAfter(3600), rules: [rule])
        await harness.drop("a.png")
        let file = try harness.file(named: "a.png")
        #expect(file.state == .scheduled && file.scheduleDuration == 7200 && file.viaRule)
    }

    @Test func pendingFilesGetTheDefaultWhenTheOptionIsSwitchedOn() async throws {
        let harness = try await harness(auto: false)
        await harness.drop("a.pdf")
        #expect(try harness.file(named: "a.pdf").state == .pending)
        var settings = await harness.engine.currentSettings
        settings.autoApplyDefault = true
        try await harness.engine.updateSettings(settings)
        let file = try harness.file(named: "a.pdf")
        #expect(file.state == .kept && file.resolution == .defaultKept)
    }
}
