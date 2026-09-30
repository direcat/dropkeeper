import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

/// Records launch-at-login requests instead of touching the real login item.
@MainActor
private final class LoginItemRecorder {
    var calls: [Bool] = []
    func apply(_ enabled: Bool) { calls.append(enabled) }
}

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
        #expect(await model.start(with: bootstrap))
        #expect(await model.addFolder(folder))
        #expect(defaults.stringArray(forKey: EngineBootstrap.folderHintsKey)?.count == 1)

        try await Task.sleep(for: .milliseconds(300))
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("report.pdf").path, contents: Data("x".utf8))
        try await waitUntil { model.queue.current != nil }
        #expect(model.queue.current?.displayName == "report.pdf")
        #expect(model.isPromptAvailable)

        await model.keepPrompted(for: try #require(model.queue.current?.id))
        #expect(model.queue.current == nil)  // the prompt moves on as soon as the decision succeeded
        try await waitUntil { model.pending.isEmpty }
        #expect(model.pending.isEmpty)

        await model.removeFolder(id: try #require(model.folders.first?.id))
        #expect(model.folders.isEmpty)
        #expect(defaults.stringArray(forKey: EngineBootstrap.folderHintsKey) == [])
        await model.stop()
    }

    @Test func loginItemIsAppliedOnFirstLaunchAndOnChangeOnly() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DropKeeperAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = LoginItemRecorder()
        let firstModel = AppModel(defaults: defaults, applyLoginItem: first.apply)
        await firstModel.start(
            with: try EngineBootstrap.make(
                databaseURL: root.appendingPathComponent("one/db.sqlite"), defaults: defaults))
        await firstModel.stop()
        #expect(first.calls == [true])

        // A later launch must not re-register: the user may have turned it off in System Settings.
        let second = LoginItemRecorder()
        let secondModel = AppModel(defaults: defaults, applyLoginItem: second.apply)
        await secondModel.start(
            with: try EngineBootstrap.make(
                databaseURL: root.appendingPathComponent("two/db.sqlite"), defaults: defaults))
        #expect(second.calls.isEmpty)
        var settings = secondModel.settings
        settings.launchAtLogin = false
        await secondModel.update(settings)
        #expect(second.calls == [false])
        await secondModel.stop()
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
        #expect(await model.start(with: bootstrap))
        #expect(await model.addFolder(folder))

        try await Task.sleep(for: .milliseconds(300))
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("setup.dmg").path, contents: Data("x".utf8))
        try await waitUntil { model.queue.current != nil }
        model.timeline.select(0)
        let id = try #require(model.queue.current?.id)

        // Both tasks run on the main actor in order: the first suspends inside the engine call,
        // the second arrives while it is still deciding. Unguarded, it would keep the just-scheduled file.
        let first = Task { await model.decide(for: id) }
        let second = Task { await model.keepPrompted(for: id) }
        await first.value
        await second.value
        try await waitUntil { model.scheduled.count == 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.scheduled.map(\.displayName) == ["setup.dmg"])
        #expect(model.pending.isEmpty)
        await model.stop()
    }

    /// Quiet mode: a waiting file opens only when picked from the list, also after Esc, and a later download
    /// doesn't open by itself.
    @Test func quietModeOpensOnlyTheReviewedFile() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DropKeeperAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
        #expect(
            await model.start(
                with: try EngineBootstrap.make(
                    databaseURL: root.appendingPathComponent("db/dropkeeper.sqlite"), defaults: defaults)))
        var settings = model.settings
        settings.quietMode = true
        await model.update(settings)
        #expect(model.settings.quietMode)
        try await Task.sleep(for: .milliseconds(300))  // the engine's first (empty) file update has arrived

        func waiting(_ id: String) -> TrackedFile {
            var file = scheduledFile(expiresIn: 0, id: id)
            file.state = .pending
            return file
        }
        model.apply([waiting("a")])
        #expect(!model.isPromptAvailable)
        model.review("a")
        #expect(model.isPromptAvailable)
        model.dismissPrompt()
        #expect(!model.isPromptAvailable)
        model.review("a")  // closed with Esc, picked again from the list
        #expect(model.isPromptAvailable)
        #expect(model.queue.current?.id == "a")
        model.dismissPrompt()
        model.apply([waiting("a"), waiting("b")])
        #expect(model.queue.current?.id == "b")
        #expect(!model.isPromptAvailable)  // the new download doesn't bypass Quiet mode
        await model.stop()
    }
}
