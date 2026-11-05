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

/// The window is the same glass one as Settings: content under a transparent titlebar. Its height is not
/// asserted: the size is only known after the first layout pass.
@MainActor
@Test func onboardingWindowIsGlass() throws {
    let suite = "DropKeeperAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    let controller = OnboardingWindowController(model: model)
    controller.show()
    let window = try #require(controller.onboardingWindow)
    #expect(window.styleMask.contains(.fullSizeContentView))
    #expect(window.titlebarAppearsTransparent)
    window.close()
}
