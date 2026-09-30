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
