import AppKit
import Testing

@testable import DropKeeper

@MainActor
@Test func runsHostedWithoutBootstrapping() {
    #expect(AppDelegate.isRunningTests)
    #expect(NSImage(named: "MenuBarIdle")?.isTemplate == true)
    #expect(NSImage(named: "Lockup") != nil)
    #expect(NSColor(named: "AccentColor") != nil)
}
