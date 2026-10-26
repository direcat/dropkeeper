import Foundation

/// State transitions that also mirror the state onto the file (xattrs, Finder tag).
/// Filesystem side effects are best-effort: the database is the source of truth.
public struct ItemActions: Sendable {
    public static let idAttribute = "net.direcat.dropkeeper.id"
    public static let expiryAttribute = "net.direcat.dropkeeper.expiry"
    public static let finderTag = "Temporary"

    let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func markPending(_ file: TrackedFile) {
        try? fs.writeXattr(Self.idAttribute, value: file.id, at: file.path)
    }

    public func schedule(_ file: inout TrackedFile, duration: TimeInterval, now: Date, tagEnabled: Bool) {
        let expiry = now.addingTimeInterval(duration)
        file.state = .scheduled
        file.expiresAt = expiry
        file.scheduleDuration = duration
        file.failureCount = 0
        file.updatedAt = now
        try? fs.writeXattr(Self.idAttribute, value: file.id, at: file.path)
        try? fs.writeXattr(Self.expiryAttribute, value: ISODate.format(expiry), at: file.path)
        if tagEnabled { try? fs.setTag(Self.finderTag, present: true, at: file.path) }
    }

    public func keep(_ file: inout TrackedFile, now: Date) {
        file.state = .kept
        file.expiresAt = nil
        file.scheduleDuration = nil
        file.failureCount = 0
        file.updatedAt = now
        clearMarks(at: file.path)
    }

    /// Removes the expiry xattr and the Finder tag; the id xattr stays.
    public func clearMarks(at path: String) {
        try? fs.removeXattr(Self.expiryAttribute, at: path)
        try? fs.setTag(Self.finderTag, present: false, at: path)
    }

    public func setTag(_ present: Bool, for files: [TrackedFile]) {
        for file in files { try? fs.setTag(Self.finderTag, present: present, at: file.path) }
    }
}
