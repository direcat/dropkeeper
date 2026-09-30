import os

public enum DropKeeperCoreInfo {
    public static let version = "0.1.0"
}

enum Log {
    static let engine = Logger(subsystem: "net.direcat.dropkeeper", category: "engine")
    static let store = Logger(subsystem: "net.direcat.dropkeeper", category: "store")
    static let watcher = Logger(subsystem: "net.direcat.dropkeeper", category: "watcher")
}
