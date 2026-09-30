import Foundation
import GRDB

public typealias FileID = String

public struct TrackedFile: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tracked_file"

    public var id: FileID
    public var folderId: Int64?
    public var path: String
    public var inode: Int64
    public var volumeId: String
    public var displayName: String
    public var kind: FileKind
    public var sizeBytes: Int64?
    public var state: FileState
    public var firstSeen: Date
    public var expiresAt: Date?
    public var trashPath: String?
    public var failureCount: Int
    public var updatedAt: Date

    /// Public memberwise initializer (declared explicitly so it is visible outside the module).
    public init(
        id: FileID, folderId: Int64?, path: String, inode: Int64, volumeId: String, displayName: String,
        kind: FileKind, sizeBytes: Int64?, state: FileState, firstSeen: Date, expiresAt: Date?,
        trashPath: String?, failureCount: Int, updatedAt: Date
    ) {
        self.id = id
        self.folderId = folderId
        self.path = path
        self.inode = inode
        self.volumeId = volumeId
        self.displayName = displayName
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.state = state
        self.firstSeen = firstSeen
        self.expiresAt = expiresAt
        self.trashPath = trashPath
        self.failureCount = failureCount
        self.updatedAt = updatedAt
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case folderId = "folder_id"
        case path, inode
        case volumeId = "volume_id"
        case displayName = "display_name"
        case kind
        case sizeBytes = "size_bytes"
        case state
        case firstSeen = "first_seen"
        case expiresAt = "expires_at"
        case trashPath = "trash_path"
        case failureCount = "failure_count"
        case updatedAt = "updated_at"
    }
}

extension FileKind: DatabaseValueConvertible {}
extension FileState: DatabaseValueConvertible {}

extension TrackedFile {
    /// A freshly detected item in state `pending`.
    public static func new(path: String, stat: FileStat, folderId: Int64?, now: Date) -> TrackedFile {
        let name = (path as NSString).lastPathComponent
        return TrackedFile(
            id: UUID().uuidString, folderId: folderId, path: path, inode: stat.inode, volumeId: stat.volumeId,
            displayName: name, kind: FileKind.classify(pathExtension: (name as NSString).pathExtension),
            sizeBytes: stat.size, state: .pending, firstSeen: now, expiresAt: nil, trashPath: nil,
            failureCount: 0, updatedAt: now
        )
    }
}
