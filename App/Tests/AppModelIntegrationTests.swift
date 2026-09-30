import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

/// Real engine, real FSEvents, temp database and temp watched folder.
@MainActor
@Suite(.serialized) struct AppModelIntegrationTests {
    private func tempDir() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("DropKeeperAppTests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func downloadAppearsInQueueAndKeepRemovesIt() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "DropKeeperAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let bootstrap = try EngineBootstrap.make(
            databaseURL: root.appendingPathComponent("db/dropkeeper.sqlite"), defaults: defaults)
        #expect(bootstrap.isFirstLaunch)
        let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
        await model.start(with: bootstrap)
        #expect(await model.addFolder(folder))
        #expect(defaults.stringArray(forKey: EngineBootstrap.folderHintsKey)?.count == 1)

        try await Task.sleep(for: .milliseconds(300))
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("report.pdf").path, contents: Data("x".utf8))
        try await waitUntil { model.queue.current != nil }
        #expect(model.queue.current?.displayName == "report.pdf")
        #expect(model.isPromptAvailable)

        await model.keepPrompted()
        try await waitUntil { model.queue.current == nil }
        #expect(model.pending.isEmpty)
        await model.stop()
    }

    /// A second prompt action while the first is still running must be ignored, not applied to the same files.
    @Test func secondDecisionWhileDecidingIsIgnored() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "DropKeeperAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let bootstrap = try EngineBootstrap.make(
            databaseURL: root.appendingPathComponent("db/dropkeeper.sqlite"), defaults: defaults)
        let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
        await model.start(with: bootstrap)
        #expect(await model.addFolder(folder))

        try await Task.sleep(for: .milliseconds(300))
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("setup.dmg").path, contents: Data("x".utf8))
        try await waitUntil { model.queue.current != nil }
        model.timeline.select(0)

        // Both tasks run on the main actor in order: the first suspends inside the engine call,
        // the second arrives while it is still deciding. Unguarded, it would keep the just-scheduled file.
        let first = Task { await model.decide() }
        let second = Task { await model.keepPrompted() }
        await first.value
        await second.value
        try await waitUntil { model.scheduled.count == 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.scheduled.map(\.displayName) == ["setup.dmg"])
        #expect(model.pending.isEmpty)
        await model.stop()
    }
}
