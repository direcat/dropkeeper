import Foundation
import Testing

@testable import DropKeeperCore

/// Holds `contentsEqual` calls until opened, so a test controls when a duplicate comparison ends.
private final class Gate: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func open() { semaphore.signal() }
    func wait() {
        semaphore.wait()
        semaphore.signal()
    }
}

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

    /// Same-size, different-content sibling: a candidate that turns out not to be a duplicate.
    private func addSibling(_ name: String, to harness: EngineHarness, content: Data) {
        harness.fs.createFile(
            EngineHarness.downloads + "/" + name, content: content, added: Date(timeIntervalSince1970: 0))
    }

    /// Blocks every comparison until the returned gate is opened.
    private func hold(_ harness: EngineHarness) -> Gate {
        let gate = Gate()
        harness.fs.contentsEqualHook = { _, _ in gate.wait() }
        return gate
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
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        // Rule-matched: nothing is observable until the comparison ends.
        #expect(try harness.files().isEmpty)
        gate.open()
        await harness.settleDuplicateChecks()
        let file = try #require(try harness.files().first)
        #expect(file.state == .pending)
        #expect(file.duplicateOf == "a.png")
        #expect(file.scheduleDuration == 3600)
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
        let gate = hold(harness)
        await dropContent("report (1).pdf", in: harness)
        // The prompt record exists right away; the hint follows the comparison.
        #expect(try harness.files().map(\.duplicateOf) == [nil])
        gate.open()
        await harness.settleDuplicateChecks()
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

    @Test func duplicateKeepsTheRuleAfterTheGracePeriod() async throws {
        let harness = try await harness(rules: [imagesRule()])
        harness.fs.createFile(
            EngineHarness.downloads + "/a.png", content: content, added: Date(timeIntervalSince1970: 0))
        await dropContent("b.png", in: harness)
        await harness.settleDuplicateChecks()
        let grace = await harness.engine.currentSettings.gracePeriod
        await harness.advance(grace + 1)
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.scheduleDuration == 3600)
        #expect(file.expiresAt == harness.time.now().addingTimeInterval(3600))
    }

    @Test func sameSizeNonDuplicateIsScheduledByTheRuleOnce() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: Data("other byte".utf8))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        #expect(try harness.files().isEmpty)
        gate.open()
        await harness.settleDuplicateChecks()
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.duplicateOf == nil)
        let note = await harness.nextNotification { if case .ruleApplied = $0 { true } else { false } }
        guard case .ruleApplied(let applications) = try #require(note) else { return }
        #expect(applications.map(\.id) == [file.id])
        #expect(try harness.files().count == 1)
    }

    @Test func fileDeletedDuringTheCheckIsDropped() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: content)
        let fs = harness.fs
        fs.contentsEqualHook = { first, _ in fs.delete(first) }
        await dropContent("b.png", in: harness)
        await harness.settleDuplicateChecks()
        #expect(try harness.files().isEmpty)
        let note = await harness.nextNotification(timeout: .milliseconds(200)) {
            if case .ruleApplied = $0 { true } else { false }
        }
        #expect(note == nil)
    }

    @Test func ruleApplicationCarriesTheRuleId() async throws {
        let rule = imagesRule()
        let harness = try await harness(rules: [rule])
        await harness.drop("a.png")
        let note = await harness.nextNotification { if case .ruleApplied = $0 { true } else { false } }
        guard case .ruleApplied(let applications) = try #require(note) else { return }
        #expect(applications.map(\.ruleId) == [rule.id])
    }

    @Test func fileReplacedDuringTheCheckIsDetectedAgain() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: content)
        let fs = harness.fs
        let path = EngineHarness.downloads + "/b.png"
        let replacement = Data("different and longer".utf8)
        let now = harness.time.now()
        fs.contentsEqualHook = { first, _ in
            guard first == path else { return }
            fs.delete(path)
            fs.createFile(path, content: replacement, added: now)
        }
        await dropContent("b.png", in: harness)
        await harness.settleDuplicateChecks()
        #expect(try harness.files().isEmpty)
        fs.contentsEqualHook = nil
        await harness.advance(1)
        await harness.advance(1)
        await harness.settleDuplicateChecks()
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.sizeBytes == Int64(replacement.count))
        #expect(try harness.files().count == 1)
    }

    @Test func pollDuringTheCheckKeepsTheFileObserved() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: Data("other byte".utf8))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        await harness.advance(2)  // the entry is ready again while the check is still running
        gate.open()
        await harness.settleDuplicateChecks()
        await harness.advance(2)
        #expect(try harness.files().map(\.state) == [.scheduled])
    }

    @Test func stopWaitsForTheCheckAndAppliesTheRule() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: Data("other byte".utf8))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        #expect(try harness.files().isEmpty)
        let release = Task {
            try await Task.sleep(for: .milliseconds(100))
            gate.open()
        }
        await harness.engine.stop()
        try await release.value
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.expiresAt == harness.time.now().addingTimeInterval(3600))
    }

    @Test func stopWaitsForTheCheckAndKeepsTheDuplicate() async throws {
        let harness = try await harness(rules: [imagesRule()])
        harness.fs.createFile(
            EngineHarness.downloads + "/a.png", content: content, added: Date(timeIntervalSince1970: 0))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        let release = Task {
            try await Task.sleep(for: .milliseconds(100))
            gate.open()
        }
        await harness.engine.stop()
        try await release.value
        let file = try #require(try harness.files().first)
        #expect(file.state == .pending)
        #expect(file.duplicateOf == "a.png")
        #expect(file.scheduleDuration == 3600)
    }

    @Test func stopTimeoutInsertsAPlainPendingRecord() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: Data("other byte".utf8))
        let gate = hold(harness)  // never opened before stop returns
        await dropContent("b.png", in: harness)
        await harness.engine.stop(drainTimeout: .milliseconds(100))
        let file = try #require(try harness.files().first)
        #expect(file.state == .pending)
        #expect(file.expiresAt == nil)
        #expect(try harness.files().count == 1)
        gate.open()
        await harness.settleDuplicateChecks()
        #expect(try harness.files().count == 1)
    }

    @Test func ruleRemovedDuringTheCheckLeavesAPendingRecord() async throws {
        let harness = try await harness(rules: [imagesRule()])
        addSibling("a.png", to: harness, content: Data("other byte".utf8))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        var settings = await harness.engine.currentSettings
        settings.rules = []
        try await harness.engine.updateSettings(settings)
        gate.open()
        await harness.settleDuplicateChecks()
        #expect(try harness.files().map(\.state) == [.pending])
    }

    @Test func detectionTurnedOffDuringTheCheckIgnoresTheVerdict() async throws {
        let harness = try await harness(rules: [imagesRule()])
        harness.fs.createFile(
            EngineHarness.downloads + "/a.png", content: content, added: Date(timeIntervalSince1970: 0))
        let gate = hold(harness)
        await dropContent("b.png", in: harness)
        var settings = await harness.engine.currentSettings
        settings.duplicateDetection = false
        try await harness.engine.updateSettings(settings)
        gate.open()
        await harness.settleDuplicateChecks()
        let file = try #require(try harness.files().first)
        #expect(file.state == .scheduled)
        #expect(file.duplicateOf == nil)
    }
}
