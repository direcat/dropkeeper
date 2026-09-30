import Foundation
import Synchronization

@testable import DropKeeperCore

final class StubEventSource: FolderEventSource {
    let events: AsyncStream<[FolderEvent]>
    private let continuation: AsyncStream<[FolderEvent]>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream(of: [FolderEvent].self) }
    func stop() { continuation.finish() }
}

final class EventIds: Sendable {
    private let value = Mutex<UInt64>(100)
    func current() -> UInt64 { value.withLock { $0 } }
    func next() -> UInt64 {
        value.withLock {
            $0 += 1
            return $0
        }
    }
}

struct EngineHarness {
    static let downloads = "/fake/Users/me/Downloads"
    static let desktop = "/fake/Users/me/Desktop"

    let fs = FakeFileSystem()
    let time = TestTimeSource()
    let ids = EventIds()
    let store: FileStore
    let engine: DropKeeperEngine

    init(
        store: FileStore? = nil, needsRecovery: Bool = false, hints: [String] = [],
        prepare: (FakeFileSystem) -> Void = { _ in }
    ) throws {
        fs.mkdir("/fake")
        fs.mkdir("/fake/Users")
        fs.mkdir("/fake/Users/me")
        fs.mkdir(Self.downloads)
        fs.mkdir(Self.desktop)
        fs.mkdir("/fake/Users/me/Documents")
        prepare(fs)
        let store = try store ?? FileStore.inMemory()
        self.store = store
        let ids = self.ids
        engine = DropKeeperEngine(
            environment: EngineEnvironment(
                store: store, fs: fs, time: time,
                makeEventSource: { _, _ in StubEventSource() },
                currentEventId: { ids.current() },
                needsRecovery: needsRecovery, recoveryFolderHints: hints, automaticTimer: false))
    }

    /// Starts the engine with Downloads watched.
    @discardableResult
    func startWithDownloads() async throws -> WatchedFolder {
        try await engine.start()
        return try await engine.addFolder(path: Self.downloads)
    }

    func event(_ path: String, _ flags: FolderEventFlags) async {
        await engine.handle(events: [FolderEvent(path: path, flags: flags, id: ids.next())])
    }

    /// Simulates a finished download: file appears, event arrives, size is stable for 1 s.
    @discardableResult
    func drop(_ name: String, in folder: String = EngineHarness.downloads, size: Int64 = 100) async -> String {
        let path = folder + "/" + name
        fs.createFile(path, size: size, added: time.now())
        await event(path, [.created, .isFile])
        time.advance(by: 1)
        await engine.tick()
        return path
    }

    func advance(_ seconds: TimeInterval) async {
        time.advance(by: seconds)
        await engine.tick()
    }

    func files(_ states: [FileState] = FileState.allCases) throws -> [TrackedFile] {
        try store.files(in: states)
    }

    /// First notification matching `predicate` (notifications are buffered). Call at most once per test:
    /// AsyncStream supports a single consumer.
    func nextNotification(
        timeout: Duration = .seconds(2), where predicate: @escaping @Sendable (EngineNotification) -> Bool
    ) async -> EngineNotification? {
        let stream = engine.notifications
        return await withTaskGroup(of: EngineNotification?.self) { group in
            group.addTask {
                for await note in stream where predicate(note) { return note }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
