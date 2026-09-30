import DropKeeperCore
import Foundation

enum EngineBootstrap {
    static let folderHintsKey = "watchedFolderPaths"

    struct Decision: Equatable {
        let needsRecovery: Bool
        let isFirstLaunch: Bool
    }

    struct Result: Sendable {
        let engine: DropKeeperEngine
        let isFirstLaunch: Bool
    }

    /// A new database with remembered folders means the database was lost: recover, don't onboard.
    static func decide(isNew: Bool, recoveredFromCorruption: Bool, hints: [String]) -> Decision {
        Decision(
            needsRecovery: recoveredFromCorruption || (isNew && !hints.isEmpty),
            isFirstLaunch: isNew && hints.isEmpty && !recoveredFromCorruption)
    }

    static func databaseURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("DropKeeper/dropkeeper.sqlite")
    }

    static func make(databaseURL: URL, defaults: UserDefaults) throws -> Result {
        let opened = try FileStore.open(at: databaseURL)
        let hints = defaults.stringArray(forKey: folderHintsKey) ?? []
        let decision = decide(
            isNew: opened.isNew, recoveredFromCorruption: opened.recoveredFromCorruption, hints: hints)
        let environment = EngineEnvironment.live(
            store: opened.store, needsRecovery: decision.needsRecovery, recoveryFolderHints: hints)
        return Result(engine: DropKeeperEngine(environment: environment), isFirstLaunch: decision.isFirstLaunch)
    }

    /// Adds the current folders to the hints. Never drops a hint: a folder missing at launch (e.g. on an
    /// unmounted volume) is not recovered, and its hint is needed to recover it on a later launch.
    static func rememberFolders(_ folders: [WatchedFolder], defaults: UserDefaults) {
        let hints = defaults.stringArray(forKey: folderHintsKey) ?? []
        let added = folders.map(\.path).filter { !hints.contains($0) }
        defaults.set(hints + added, forKey: folderHintsKey)
    }

    /// Removes a folder's hint; only for an explicit user removal.
    static func forgetFolder(path: String, defaults: UserDefaults) {
        let hints = defaults.stringArray(forKey: folderHintsKey) ?? []
        defaults.set(hints.filter { $0 != path }, forKey: folderHintsKey)
    }
}
