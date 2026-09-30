import CoreServices

public struct FolderEventFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let mustScanSubDirs = Self(rawValue: UInt32(kFSEventStreamEventFlagMustScanSubDirs))
    public static let idsWrapped = Self(rawValue: UInt32(kFSEventStreamEventFlagEventIdsWrapped))
    public static let historyDone = Self(rawValue: UInt32(kFSEventStreamEventFlagHistoryDone))
    public static let rootChanged = Self(rawValue: UInt32(kFSEventStreamEventFlagRootChanged))
    public static let created = Self(rawValue: UInt32(kFSEventStreamEventFlagItemCreated))
    public static let removed = Self(rawValue: UInt32(kFSEventStreamEventFlagItemRemoved))
    public static let renamed = Self(rawValue: UInt32(kFSEventStreamEventFlagItemRenamed))
    public static let modified = Self(rawValue: UInt32(kFSEventStreamEventFlagItemModified))
    public static let xattrModified = Self(rawValue: UInt32(kFSEventStreamEventFlagItemXattrMod))
    public static let isFile = Self(rawValue: UInt32(kFSEventStreamEventFlagItemIsFile))
    public static let isDirectory = Self(rawValue: UInt32(kFSEventStreamEventFlagItemIsDir))
}

public struct FolderEvent: Sendable, Equatable {
    public var path: String
    public var flags: FolderEventFlags
    public var id: UInt64

    public init(path: String, flags: FolderEventFlags, id: UInt64) {
        self.path = path
        self.flags = flags
        self.id = id
    }
}

public protocol FolderEventSource: AnyObject, Sendable {
    var events: AsyncStream<[FolderEvent]> { get }
    func stop()
}
