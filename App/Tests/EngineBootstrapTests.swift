import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

@Test func reviewFocusFirstLaunchShowsOnboardingWithoutRecovery() {
    let decision = EngineBootstrap.decide(isNew: true, recoveredFromCorruption: false, hints: [])
    #expect(decision == .init(needsRecovery: false, isFirstLaunch: true))
}

@Test func reviewFocusLostDatabaseWithHintsRecoversWithoutOnboarding() {
    let decision = EngineBootstrap.decide(isNew: true, recoveredFromCorruption: false, hints: ["/Users/me/Downloads"])
    #expect(decision == .init(needsRecovery: true, isFirstLaunch: false))
}

@Test func corruptDatabaseAlwaysRecovers() {
    #expect(EngineBootstrap.decide(isNew: false, recoveredFromCorruption: true, hints: []).needsRecovery)
    #expect(!EngineBootstrap.decide(isNew: false, recoveredFromCorruption: true, hints: []).isFirstLaunch)
}

@Test func normalLaunchDoesNothingSpecial() {
    let decision = EngineBootstrap.decide(isNew: false, recoveredFromCorruption: false, hints: ["/x"])
    #expect(decision == .init(needsRecovery: false, isFirstLaunch: false))
}

private func watched(_ path: String) -> WatchedFolder {
    WatchedFolder(
        id: nil, path: path, bookmark: nil, volumeId: "V", addedAt: Date(timeIntervalSince1970: 1_800_000_000),
        baselineEventId: 0, status: .ok)
}

private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "DropKeeperAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

/// A folder missing at launch (unmounted volume) is not recovered, but its hint must survive for the next launch.
@Test func rememberFoldersKeepsHintsOfFoldersMissingNow() throws {
    try withDefaults { defaults in
        defaults.set(["/a", "/b"], forKey: EngineBootstrap.folderHintsKey)
        EngineBootstrap.rememberFolders([watched("/a"), watched("/c")], defaults: defaults)
        #expect(defaults.stringArray(forKey: EngineBootstrap.folderHintsKey) == ["/a", "/b", "/c"])
    }
}

@Test func forgetFolderRemovesOnlyItsHint() throws {
    try withDefaults { defaults in
        defaults.set(["/a", "/b"], forKey: EngineBootstrap.folderHintsKey)
        EngineBootstrap.forgetFolder(path: "/a", defaults: defaults)
        #expect(defaults.stringArray(forKey: EngineBootstrap.folderHintsKey) == ["/b"])
    }
}
