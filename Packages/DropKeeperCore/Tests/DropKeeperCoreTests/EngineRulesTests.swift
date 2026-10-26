import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineRulesTests {
    private let content = Data("same bytes".utf8)

    private func imagesRule(folder: String = EngineHarness.downloads) -> Rule {
        Rule(name: "Images", match: .category(.images), folderPath: folder, duration: 3600)
    }

    private func harness(
        rules: [Rule], duplicateDetection: Bool = true
    ) async throws -> EngineHarness {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var settings = await harness.engine.currentSettings
        settings.rules = rules
        settings.duplicateDetection = duplicateDetection
        try await harness.engine.updateSettings(settings)
        return harness
    }

    /// `drop` with real content, so the duplicate finder can compare bytes.
    @discardableResult
    private func dropContent(_ name: String, in harness: EngineHarness) async -> String {
        let path = EngineHarness.downloads + "/" + name
        harness.fs.createFile(path, content: content, added: harness.time.now())
        await harness.event(path, [.created, .isFile])
        harness.time.advance(by: 1)
        await harness.engine.tick()
        return path
    }

    @Test func ruleSchedulesWithoutPrompt() async throws {
        let harness = try await harness(rules: [imagesRule()])
        await harness.drop("a.png")
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == harness.time.now().addingTimeInterval(3600))
        let note = await harness.nextNotification { if case .ruleApplied = $0 { true } else { false } }
        guard case .ruleApplied(let applications) = try #require(note) else { return }
        #expect(applications.map(\.ruleName) == ["Images"])
        #expect(applications.map(\.id) == [file.id])
    }

    @Test func ruleMatchIsNeverStoredAsPending() async throws {
        let harness = try await harness(rules: [imagesRule()])
        let observation = harness.engine.fileUpdates(in: [.pending])
        let sawPending = Task { () -> Bool in
            var seen = false
            do {
                for try await files in observation where !files.isEmpty { seen = true }
            } catch {}
            return seen
        }
        await harness.drop("a.png")
        try await Task.sleep(for: .milliseconds(200))
        sawPending.cancel()
        #expect(await sawPending.value == false)
        #expect(try harness.files().map(\.state) == [.scheduled])
    }

    @Test func duplicateBeatsRule() async throws {
        let harness = try await harness(rules: [imagesRule()])
        harness.fs.createFile(
            EngineHarness.downloads + "/a.png", content: content, added: Date(timeIntervalSince1970: 0))
        await dropContent("b.png", in: harness)
        let file = try #require(try harness.files().first)
        #expect(file.state == .pending)
        #expect(file.duplicateOf == "a.png")
        let note = await harness.nextNotification(timeout: .milliseconds(200)) {
            if case .ruleApplied = $0 { true } else { false }
        }
        #expect(note == nil)
    }

    @Test func duplicateDetectionOff() async throws {
        let harness = try await harness(rules: [imagesRule()], duplicateDetection: false)
        harness.fs.createFile(
            EngineHarness.downloads + "/a.png", content: content, added: Date(timeIntervalSince1970: 0))
        await dropContent("b.png", in: harness)
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.duplicateOf == nil)
    }

    @Test func duplicateWithoutRuleIsFlaggedOnThePendingRecord() async throws {
        let harness = try await harness(rules: [])
        harness.fs.createFile(
            EngineHarness.downloads + "/report.pdf", content: content, added: Date(timeIntervalSince1970: 0))
        await dropContent("report (1).pdf", in: harness)
        let file = try #require(try harness.files().first)
        #expect(file.state == .pending)
        #expect(file.duplicateOf == "report.pdf")
    }

    @Test func rulesDoNotTouchExistingFiles() async throws {
        let harness = try await harness(rules: [])
        await harness.drop("a.png")
        var settings = await harness.engine.currentSettings
        settings.rules = [imagesRule()]
        try await harness.engine.updateSettings(settings)
        await harness.advance(10)
        #expect(try harness.files().map(\.state) == [.pending])
    }

    @Test func ruleForAnotherFolderLeavesFileToThePrompt() async throws {
        let harness = try await harness(rules: [imagesRule(folder: EngineHarness.desktop)])
        await harness.drop("a.png")
        #expect(try harness.files().map(\.state) == [.pending])
    }
}
