import Foundation
import GRDB

public enum FolderStatus: String, Codable, Sendable {
    case ok, noAccess, unavailable
}

extension FolderStatus: DatabaseValueConvertible {}

public struct WatchedFolder: Codable, Sendable, Equatable, Identifiable, FetchableRecord,
    MutablePersistableRecord
{
    public static let databaseTableName = "watched_folder"

    public var id: Int64?
    public var path: String
    public var bookmark: Data?
    public var volumeId: String
    public var addedAt: Date
    public var baselineEventId: UInt64
    public var status: FolderStatus

    public init(
        id: Int64?, path: String, bookmark: Data?, volumeId: String, addedAt: Date,
        baselineEventId: UInt64, status: FolderStatus
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.volumeId = volumeId
        self.addedAt = addedAt
        self.baselineEventId = baselineEventId
        self.status = status
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, path, bookmark
        case volumeId = "volume_id"
        case addedAt = "added_at"
        case baselineEventId = "baseline_event_id"
        case status
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// True for any path strictly inside this folder (at any depth).
    public func contains(_ other: String) -> Bool {
        other.hasPrefix(path + "/")
    }
}
