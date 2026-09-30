import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private let downloads = URL(fileURLWithPath: "/Users/me/Downloads")

private func folder(_ status: FolderStatus) -> WatchedFolder {
    WatchedFolder(
        id: 1, path: downloads.path, bookmark: nil, volumeId: "V", addedAt: Date(), baselineEventId: 0, status: status)
}

@Test func onboardingSteps() {
    #expect(OnboardingStep.state(folders: [], downloads: downloads) == .needsAccess)
    #expect(OnboardingStep.state(folders: [folder(.ok)], downloads: downloads) == .granted)
    #expect(OnboardingStep.state(folders: [folder(.noAccess)], downloads: downloads) == .denied)
}

@Test func safeDebugRunOnboardsTheTestFolder() {
    let real = URL(fileURLWithPath: "/Users/me/Downloads")
    #expect(
        OnboardingFolder.target(downloads: real, dbPath: "/tmp/dk.sqlite", watch: "/tmp/dk-watch").path
            == "/tmp/dk-watch")
    #expect(OnboardingFolder.target(downloads: real, dbPath: nil, watch: "/tmp/dk-watch") == real)
    #expect(OnboardingFolder.target(downloads: real, dbPath: "/tmp/dk.sqlite", watch: nil) == real)
    #expect(OnboardingFolder.target(downloads: real, dbPath: nil, watch: nil) == real)
}
