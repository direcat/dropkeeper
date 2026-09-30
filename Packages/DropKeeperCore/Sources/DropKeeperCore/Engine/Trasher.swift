import Foundation

public enum DisposeResult: Sendable, Equatable {
    case disposed, retryScheduled, failed
}

public enum TrasherError: Error, Equatable {
    case notUndoable
}

public struct Trasher: Sendable {
    /// Delays before retry 1, 2 and 3. After the last retry fails the item becomes `failed`.
    public static let retryDelays: [TimeInterval] = [1, 5, 30]

    let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// One disposal attempt. Never falls back from Trash to permanent deletion.
    public func dispose(_ file: inout TrackedFile, mode: DeleteMode, now: Date) -> DisposeResult {
        do {
            switch mode {
            case .trash:
                file.trashPath = try fs.moveToTrash(file.path)
            case .permanent:
                try fs.removeItem(file.path)
                file.trashPath = nil
            }
            file.state = .trashed
            file.failureCount = 0
            file.updatedAt = now
            return .disposed
        } catch {
            Log.engine.error("Dispose failed: \(error.localizedDescription, privacy: .private)")
            file.failureCount += 1
            file.updatedAt = now
            guard file.failureCount <= Self.retryDelays.count else {
                file.state = .failed
                file.expiresAt = nil
                return .failed
            }
            file.expiresAt = now.addingTimeInterval(Self.retryDelays[file.failureCount - 1])
            return .retryScheduled
        }
    }

    public func undo(_ file: inout TrackedFile, now: Date) throws {
        guard file.state == .trashed, let trashPath = file.trashPath else { throw TrasherError.notUndoable }
        let target = uniquePath(for: file.path)
        try fs.moveItem(from: trashPath, to: target)
        file.path = target
        file.displayName = (target as NSString).lastPathComponent
        file.trashPath = nil
        file.state = .kept
        file.expiresAt = nil
        file.updatedAt = now
    }

    public func uniquePath(for path: String) -> String {
        guard fs.stat(path) != nil else { return path }
        let directory = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory + "/" + candidateName
            if fs.stat(candidate) == nil { return candidate }
            index += 1
        }
    }
}
