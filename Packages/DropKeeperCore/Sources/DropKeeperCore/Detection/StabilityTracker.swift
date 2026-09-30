import Foundation

/// Tracks candidate paths until their size has not changed for `stableInterval`.
public struct StabilityTracker: Sendable {
    private struct Entry: Sendable {
        var size: Int64
        var lastChange: Date
    }

    public var stableInterval: TimeInterval
    private var entries: [String: Entry] = [:]

    public init(stableInterval: TimeInterval = 1) {
        self.stableInterval = stableInterval
    }

    public var isEmpty: Bool { entries.isEmpty }

    public mutating func observe(_ path: String, size: Int64, now: Date) {
        if let existing = entries[path], existing.size == size { return }
        entries[path] = Entry(size: size, lastChange: now)
    }

    public mutating func poll(now: Date, fs: any FileSystem) -> [(path: String, stat: FileStat)] {
        var ready: [(path: String, stat: FileStat)] = []
        for (path, entry) in entries {
            guard let stat = fs.stat(path) else {
                entries[path] = nil
                continue
            }
            if stat.size != entry.size {
                entries[path] = Entry(size: stat.size, lastChange: now)
            } else if now.timeIntervalSince(entry.lastChange) >= stableInterval {
                ready.append((path, stat))
                entries[path] = nil
            }
        }
        return ready.sorted { $0.path < $1.path }
    }
}
