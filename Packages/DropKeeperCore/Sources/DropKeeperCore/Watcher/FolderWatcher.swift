import CoreServices
import Foundation
import Synchronization

public enum FolderWatcherError: Error {
    case couldNotCreateStream
}

/// One FSEvents stream over the given folders, file-level events, delivered as batches.
public final class FolderWatcher: FolderEventSource {
    public let events: AsyncStream<[FolderEvent]>
    private let continuation: AsyncStream<[FolderEvent]>.Continuation
    private let queue = DispatchQueue(label: "net.direcat.dropkeeper.fsevents")
    private let stream = Mutex<FSEventStreamRef?>(nil)
    private static let queueKey = DispatchSpecificKey<Void>()

    public static func currentEventId() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// Creates and immediately starts the stream. `since` replays journaled events after that id.
    public init(paths: [String], since: UInt64?, latency: TimeInterval = 0.3) throws {
        let (eventStream, eventContinuation) = AsyncStream.makeStream(of: [FolderEvent].self)
        events = eventStream
        continuation = eventContinuation
        try start(paths: paths, since: since, latency: latency)
    }

    private func start(paths: [String], since: UInt64?, latency: TimeInterval) throws {
        queue.setSpecific(key: Self.queueKey, value: ())
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        let sinceId = since ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        // Everything non-Sendable (context, stream ref) is created inside the lock so it
        // stays in the mutex's region.
        try stream.withLock { value in
            // The context holds an unretained pointer to self; stop() (also run from deinit)
            // invalidates the stream and drains the queue before the object goes away,
            // so the callback never outlives it.
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
                copyDescription: nil)
            guard
                let created = FSEventStreamCreate(
                    kCFAllocatorDefault, Self.callback, &context, paths as CFArray, sinceId, latency, flags)
            else { throw FolderWatcherError.couldNotCreateStream }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            value = created
        }
    }

    /// Runs on `queue`: converts one FSEvents batch and yields it to `events`.
    private static let callback: FSEventStreamCallback = { _, info, count, rawPaths, rawFlags, rawIds in
        guard let info else { return }
        let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
        var batch: [FolderEvent] = []
        batch.reserveCapacity(count)
        for index in 0..<min(count, paths.count) {
            batch.append(
                FolderEvent(
                    path: paths[index], flags: FolderEventFlags(rawValue: rawFlags[index]),
                    id: rawIds[index]))
        }
        watcher.continuation.yield(batch)
    }

    /// Stops and releases the stream and finishes `events`. Idempotent.
    public func stop() {
        let stopped = stream.withLock { value -> Bool in
            guard let current = value else { return false }
            value = nil
            FSEventStreamStop(current)
            FSEventStreamInvalidate(current)
            FSEventStreamRelease(current)
            return true
        }
        guard stopped else { return }
        // Wait out a callback that may already be running, unless we are on the queue ourselves.
        if DispatchQueue.getSpecific(key: Self.queueKey) == nil {
            queue.sync {}
        }
        continuation.finish()
    }

    deinit {
        stop()
    }
}
