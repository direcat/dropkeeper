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

    @Test func quietModeSwitchedOnWithTheOptionAlreadyStoredResolvesWaitingFiles() async throws {
        let harness = try await harness(quiet: false)
        await harness.drop("a.pdf")
        #expect(try harness.file(named: "a.pdf").state == .pending)
        var settings = await harness.engine.currentSettings
        settings.quietMode = true
        try await harness.engine.updateSettings(settings)
        let file = try harness.file(named: "a.pdf")
        #expect(file.state == .kept && file.resolution == .defaultKept)
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

@Suite(.serialized) struct EngineAutoDuplicateTests {
    private let content = Data("same bytes".utf8)

    private func harness(
        detect: Bool = true, mode: DeleteMode = .trash, auto: Bool = true, rules: [Rule]? = nil
    ) async throws -> EngineHarness {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.quietMode = true
        settings.autoApplyDefault = auto
        settings.duplicateDetection = detect
        settings.deleteMode = mode
        if let rules { settings.rules = rules }
        try await harness.engine.updateSettings(settings)
        harness.fs.createFile(
            EngineHarness.downloads + "/report.png", content: content, added: Date(timeIntervalSince1970: 0))
        return harness
    }

    private func dropDuplicate(_ harness: EngineHarness, name: String = "report (1).png", data: Data? = nil) async {
        let path = EngineHarness.downloads + "/" + name
        harness.fs.createFile(path, content: data ?? content, added: harness.time.now())
        await harness.event(path, [.created, .isFile])
        harness.time.advance(by: 1)
        await harness.engine.tick()
        await harness.settleDuplicateChecks()
    }

    @Test func duplicateIsTrashedAtOnce() async throws {
        let harness = try await harness()
        await dropDuplicate(harness)
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .trashed && file.resolution == .deletedNow && file.duplicateOf == "report.png")
        #expect(file.trashPath != nil)
        #expect(try harness.store.statistics().duplicatesDeleted == 1)
    }

    @Test func duplicateIsDeletedPermanentlyInPermanentMode() async throws {
        let harness = try await harness(mode: .permanent)
        await dropDuplicate(harness)
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .trashed && file.trashPath == nil && file.resolution == .deletedNow)
        #expect(try harness.store.statistics().duplicatesDeleted == 1)
    }

    @Test func duplicateBeatsAMatchingRule() async throws {
        let rule = Rule(
            name: "Images", match: .category(.images), folderPath: EngineHarness.downloads, duration: 3600)
        let harness = try await harness(rules: [rule])
        await dropDuplicate(harness)
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .trashed && file.resolution == .deletedNow)
    }

    @Test func detectionOffUsesTheDefaultPath() async throws {
        let harness = try await harness(detect: false)
        await dropDuplicate(harness)
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .kept && file.resolution == .defaultKept)
    }

    @Test func nonDuplicateUsesTheDefaultPath() async throws {
        let harness = try await harness()
        await dropDuplicate(harness, data: Data("diff bytes".utf8))
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .kept && file.resolution == .defaultKept && file.duplicateOf == nil)
    }

    @Test func optionOffKeepsTheDuplicateWaiting() async throws {
        let harness = try await harness(auto: false)
        await dropDuplicate(harness)
        let file = try harness.file(named: "report (1).png")
        #expect(file.state == .pending && file.duplicateOf == "report.png")
    }

    /// Two identical new files in one poll (a double-clicked download) must never delete each other.
    private func dropPair(_ harness: EngineHarness) async {
        let paths = ["x.pdf", "x (1).pdf"].map { EngineHarness.downloads + "/" + $0 }
        for path in paths { harness.fs.createFile(path, content: content, added: harness.time.now()) }
        for path in paths { await harness.event(path, [.created, .isFile]) }
        harness.time.advance(by: 1)
        await harness.engine.tick()
        await harness.settleDuplicateChecks()
        await harness.engine.tick()
    }

    @Test(arguments: [DeleteMode.trash, DeleteMode.permanent])
    func aPairOfNewIdenticalFilesLosesOnlyTheCopy(mode: DeleteMode) async throws {
        let harness = try await harness(mode: mode)
        try harness.fs.removeItem(EngineHarness.downloads + "/report.png")
        await dropPair(harness)
        let original = try harness.file(named: "x.pdf")
        let copy = try harness.file(named: "x (1).pdf")
        #expect(original.state == .kept)
        #expect(copy.state == .trashed && copy.duplicateOf == "x.pdf")
        #expect(harness.fs.exists(EngineHarness.downloads + "/x.pdf"))
        #expect(!harness.fs.exists(EngineHarness.downloads + "/x (1).pdf"))
    }

    @Test func copyOfAScheduledOriginalIsNotDeleted() async throws {
        // The original is still scheduled for deletion, so deleting the copy now could lose the last one.
        let harness = try await harness(rules: [
            Rule(name: "Images", match: .category(.images), folderPath: EngineHarness.downloads, duration: 3600)
        ])
        try harness.fs.removeItem(EngineHarness.downloads + "/report.png")
        let original = EngineHarness.downloads + "/pic.png"
        harness.fs.createFile(original, content: content, added: harness.time.now())
        await harness.event(original, [.created, .isFile])
        harness.time.advance(by: 1)
        await harness.engine.tick()
        await harness.settleDuplicateChecks()
        #expect(try harness.file(named: "pic.png").state == .scheduled)
        await dropDuplicate(harness, name: "pic (1).png")
        let copy = try harness.file(named: "pic (1).png")
        #expect(copy.state != .trashed && copy.duplicateOf == nil)
        #expect(harness.fs.exists(EngineHarness.downloads + "/pic (1).png"))
    }
}
