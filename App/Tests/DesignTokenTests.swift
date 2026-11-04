import AppKit
import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

private func scheduled(expiresIn seconds: TimeInterval, length: TimeInterval, now: Date) -> TrackedFile {
    var file = scheduledFile(expiresIn: seconds)
    file.expiresAt = now.addingTimeInterval(seconds)
    file.scheduleDuration = length
    return file
}

@Test func ringShareIsRemainingOverLengthClamped() {
    let now = Date()
    #expect(RingProgress.share(for: scheduled(expiresIn: 30, length: 120, now: now), now: now) == 0.25)
    #expect(RingProgress.share(for: scheduled(expiresIn: 300, length: 120, now: now), now: now) == 1)  // after Extend
    #expect(RingProgress.share(for: scheduled(expiresIn: -5, length: 120, now: now), now: now) == 0)
}

@Test func ringShareIsZeroWithoutExpiryOrLength() {
    let now = Date()
    var noExpiry = scheduled(expiresIn: 30, length: 120, now: now)
    noExpiry.expiresAt = nil
    #expect(RingProgress.share(for: noExpiry, now: now) == 0)
    #expect(RingProgress.share(for: scheduled(expiresIn: 30, length: 0, now: now), now: now) == 0)
}

@Test func ringWarnsNearExpiry() {
    let now = Date()
    #expect(RingProgress.isWarning(for: scheduled(expiresIn: 8, length: 3600, now: now), now: now))
    #expect(RingProgress.isWarning(for: scheduled(expiresIn: 300, length: 86_400, now: now), now: now))  // < 10 %
    #expect(!RingProgress.isWarning(for: scheduled(expiresIn: 3000, length: 3600, now: now), now: now))
}

@MainActor
@Test func appearanceMapsToNSAppearance() {
    let before = NSApp.appearance
    defer { NSApp.appearance = before }
    AppearanceController.apply(.dark)
    #expect(NSApp.appearance?.name == .darkAqua)
    AppearanceController.apply(.light)
    #expect(NSApp.appearance?.name == .aqua)
    AppearanceController.apply(.auto)
    #expect(NSApp.appearance == nil)
}
