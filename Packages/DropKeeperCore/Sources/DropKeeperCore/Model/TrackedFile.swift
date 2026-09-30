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
