import Foundation
import GRDB

public enum MetaKey: String, Sendable {
    case lastEventId = "last_event_id"
    case lastHeartbeatAt = "last_heartbeat_at"
    case lastMaintenanceAt = "last_maintenance_at"
    case lastHistoryClearAt = "last_history_clear_at"
}

public struct StoreOpenResult: Sendable {
    public let store: FileStore
    public let isNew: Bool
    public let recoveredFromCorruption: Bool
}

private struct KeyValueRow: Codable, FetchableRecord {
    var key: String
    var value: String
}

public final class FileStore: Sendable {
    private let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.prepare(writer)
    }

    public static func inMemory() throws -> FileStore {
        try FileStore(writer: DatabaseQueue())
    }

    /// Opens (or creates) the database. A corrupt file is renamed to `<name>.corrupt-<timestamp>` and replaced.
    public static func open(at url: URL, now: Date = Date()) throws -> StoreOpenResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let isNew = !fileManager.fileExists(atPath: url.path)
        do {
            let store = try FileStore(writer: DatabasePool(path: url.path))
            try store.checkIntegrity()
            return StoreOpenResult(store: store, isNew: isNew, recoveredFromCorruption: false)
        } catch let error as DatabaseError
            where error.resultCode.primaryResultCode == .SQLITE_CORRUPT
            || error.resultCode.primaryResultCode == .SQLITE_NOTADB
        {
            Log.store.error("Database corrupt (\(error.resultCode.rawValue)); moving aside")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .gmt
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let aside = url.path + ".corrupt-" + formatter.string(from: now)
            try fileManager.moveItem(atPath: url.path, toPath: aside)
            for suffix in ["-wal", "-shm"] { try? fileManager.removeItem(atPath: url.path + suffix) }
            let store = try FileStore(writer: DatabasePool(path: url.path))
            return StoreOpenResult(store: store, isNew: false, recoveredFromCorruption: true)
        }
    }

    private func checkIntegrity() throws {
        let result = try writer.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }
        guard result == "ok" else { throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: result) }
    }

    private static func prepare(_ writer: any DatabaseWriter) throws {
        try writer.writeWithoutTransaction { db in
            let tables = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master") ?? 0
            if tables == 0 {
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
                try db.execute(sql: "VACUUM")
            }
        }
        try migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "watched_folder") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("path", .text).notNull().unique()
                table.column("bookmark", .blob)
                table.column("volume_id", .text).notNull()
                table.column("added_at", .datetime).notNull()
                table.column("baseline_event_id", .integer).notNull()
                table.column("status", .text).notNull()
            }
            try db.create(table: "tracked_file") { table in
                table.primaryKey("id", .text)
                table.column("folder_id", .integer).references("watched_folder", onDelete: .setNull)
                table.column("path", .text).notNull()
                table.column("inode", .integer).notNull()
                table.column("volume_id", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("size_bytes", .integer)
                table.column("state", .text).notNull()
                table.column("first_seen", .datetime).notNull()
                table.column("expires_at", .datetime)
                table.column("trash_path", .text)
                table.column("failure_count", .integer).notNull().defaults(to: 0)
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "tracked_file_state_expires", on: "tracked_file", columns: ["state", "expires_at"])
            try db.create(index: "tracked_file_identity", on: "tracked_file", columns: ["inode", "volume_id"])
            try db.create(index: "tracked_file_state_updated", on: "tracked_file", columns: ["state", "updated_at"])
            try db.create(index: "tracked_file_folder", on: "tracked_file", columns: ["folder_id"])
            try db.create(index: "tracked_file_path", on: "tracked_file", columns: ["path"])
            try db.create(table: "setting") { table in
                table.primaryKey("key", .text)
                table.column("value", .text).notNull()
            }
            try db.create(table: "meta") { table in
                table.primaryKey("key", .text)
                table.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "tracked_file") { table in
                table.add(column: "schedule_duration", .double)
                table.add(column: "duplicate_of", .text)
            }
        }
        return migrator
    }

    // MARK: Folders

    public func folders() throws -> [WatchedFolder] {
        try writer.read { try WatchedFolder.order(WatchedFolder.CodingKeys.id).fetchAll($0) }
    }

    public func insertFolder(_ folder: WatchedFolder) throws -> WatchedFolder {
        try writer.write { db in
            var copy = folder
            try copy.insert(db)
            return copy
        }
    }

    public func updateFolder(_ folder: WatchedFolder) throws {
        try writer.write { try folder.update($0) }
    }

    public func deleteFolder(id: Int64) throws {
        _ = try writer.write { try WatchedFolder.deleteOne($0, key: id) }
    }

    // MARK: Files

    public func insert(_ file: TrackedFile) throws {
        try writer.write { try file.insert($0) }
    }

    public func update(_ file: TrackedFile) throws {
        try writer.write { try file.update($0) }
    }

    public func file(id: FileID) throws -> TrackedFile? {
        try writer.read { try TrackedFile.fetchOne($0, key: id) }
    }

    public func file(inode: Int64, volumeId: String, excluding: [FileState]) throws -> TrackedFile? {
        typealias Keys = TrackedFile.CodingKeys
        return try writer.read { db in
            try TrackedFile
                .filter(Keys.inode == inode && Keys.volumeId == volumeId)
                .filter(!excluding.map(\.rawValue).contains(Keys.state))
                .order(Keys.updatedAt.desc)
                .fetchOne(db)
        }
    }

    private func request(_ states: [FileState]) -> QueryInterfaceRequest<TrackedFile> {
        typealias Keys = TrackedFile.CodingKeys
        return TrackedFile.filter(states.map(\.rawValue).contains(Keys.state)).order(Keys.firstSeen, Keys.id)
    }

    public func files(in states: [FileState]) throws -> [TrackedFile] {
        try writer.read { try self.request(states).fetchAll($0) }
    }

    public func files(in states: [FileState], path: String) throws -> [TrackedFile] {
        try writer.read { try self.request(states).filter(TrackedFile.CodingKeys.path == path).fetchAll($0) }
    }

    public func files(in states: [FileState], folderId: Int64) throws -> [TrackedFile] {
        try writer.read { try self.request(states).filter(TrackedFile.CodingKeys.folderId == folderId).fetchAll($0) }
    }

    public func deleteFiles(in states: [FileState], updatedBefore date: Date) throws -> Int {
        try writer.write { db in
            try TrackedFile
                .filter(states.map(\.rawValue).contains(TrackedFile.CodingKeys.state))
                .filter(TrackedFile.CodingKeys.updatedAt < date)
                .deleteAll(db)
        }
    }

    public func optimize(vacuum: Bool) throws {
        try writer.writeWithoutTransaction { db in
            if vacuum { try db.execute(sql: "PRAGMA incremental_vacuum") }
            try db.execute(sql: "PRAGMA optimize")
        }
    }

    public func autoVacuumMode() throws -> Int {
        try writer.read { try Int.fetchOne($0, sql: "PRAGMA auto_vacuum") ?? 0 }
    }

    public func observeFiles(in states: [FileState]) -> AsyncValueObservation<[TrackedFile]> {
        let request = self.request(states)
        return ValueObservation.tracking { try request.fetchAll($0) }.values(in: writer)
    }

    // MARK: Settings & meta

    public func settings() throws -> Settings {
        let raw = try writer.read { try KeyValueRow.fetchOne($0, key: "settings", table: "setting") }
        guard let raw else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: Data(raw.value.utf8))) ?? Settings()
    }

    public func saveSettings(_ settings: Settings) throws {
        let data = try JSONEncoder().encode(settings)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                settings, .init(codingPath: [], debugDescription: "Settings JSON is not valid UTF-8"))
        }
        try writer.write { try KeyValueRow(key: "settings", value: json).save($0, table: "setting") }
    }

    public func meta(_ key: MetaKey) throws -> String? {
        try writer.read { try KeyValueRow.fetchOne($0, key: key.rawValue, table: "meta")?.value }
    }

    public func setMeta(_ key: MetaKey, _ value: String?) throws {
        try writer.write { db in
            if let value {
                try KeyValueRow(key: key.rawValue, value: value).save(db, table: "meta")
            } else {
                _ = try KeyValueRow.deleteOne(db, key: key.rawValue, table: "meta")
            }
        }
    }
}

extension KeyValueRow {
    fileprivate static func fetchOne(_ db: Database, key: String, table: String) throws -> KeyValueRow? {
        try KeyValueRow.fetchOne(db, sql: "SELECT key, value FROM \(table) WHERE key = ?", arguments: [key])
    }

    fileprivate static func deleteOne(_ db: Database, key: String, table: String) throws -> Bool {
        try db.execute(sql: "DELETE FROM \(table) WHERE key = ?", arguments: [key])
        return db.changesCount > 0
    }

    fileprivate func save(_ db: Database, table: String) throws {
        try db.execute(
            sql:
                "INSERT INTO \(table) (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            arguments: [key, value])
    }
}
