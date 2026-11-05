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

@Test func ringTintStopsAreGreenAmberRed() {
    #expect(RingProgress.blend(share: 1) == .init(from: .green, to: .green, amount: 0))
    #expect(RingProgress.blend(share: 0.5) == .init(from: .green, to: .green, amount: 0))
    #expect(RingProgress.blend(share: 0.25) == .init(from: .green, to: .amber, amount: 1))
    #expect(RingProgress.blend(share: 0.05) == .init(from: .red, to: .red, amount: 0))
    #expect(RingProgress.blend(share: 0) == .init(from: .red, to: .red, amount: 0))
    #expect(RingProgress.blend(share: -1) == .init(from: .red, to: .red, amount: 0))  // clamped
    #expect(RingProgress.blend(share: 7) == .init(from: .green, to: .green, amount: 0))
}

@Test func ringTintMovesMonotonicallyFromGreenToRed() {
    // Position along green(0) -> amber(1) -> red(2) as the share falls.
    func position(_ share: Double) -> Double {
        let blend = RingProgress.blend(share: share)
        let base: [RingStop: Double] = [.green: 0, .amber: 1, .red: 2]
        return (blend.from == blend.to ? base[blend.from]! : base[blend.from]! + blend.amount)
    }
    let shares = stride(from: 1.0, through: 0.0, by: -0.01).map { $0 }
    let positions = shares.map(position)
    #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(positions.first == 0 && positions.last == 2)
    #expect(abs(position(0.375) - 0.5) < 1e-9)  // halfway green -> amber
    #expect(abs(position(0.15) - 1.5) < 1e-9)  // halfway amber -> red
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

@Test func ringShareIsZeroWithoutExpiryOrLength() {
    let now = Date()
    var noExpiry = scheduled(expiresIn: 30, length: 120, now: now)
    noExpiry.expiresAt = nil
    #expect(RingProgress.share(for: noExpiry, now: now) == 0)
    #expect(RingProgress.share(for: scheduled(expiresIn: 30, length: 0, now: now), now: now) == 0)
}

/// A window the test owns must not release itself on close: ARC already does, and a double release crashes the
/// test host later (xcodebuild then blames whichever test runs next).
@MainActor
private func makeTestWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    return window
}

@MainActor
@Test func frontWindowLeavesAWindowClosedInTheMeantimeAlone() {
    let window = makeTestWindow()
    var activations = 0
    var pending: [@MainActor () -> Void] = []
    FrontWindow.present(window, activate: { activations += 1 }, later: { pending.append($0) })
    window.close()
    for work in pending { work() }
    #expect(activations == 1)
}

@MainActor
@Test func frontWindowActivatesNowAndAgainAfterTheCloseSettles() {
    let window = makeTestWindow()
    var activations = 0
    var pending: [@MainActor () -> Void] = []
    FrontWindow.present(window, activate: { activations += 1 }, later: { pending.append($0) })
    #expect(activations == 1)
    #expect(window.isVisible)
    for work in pending { work() }
    #expect(activations == 2)
    window.close()
}
