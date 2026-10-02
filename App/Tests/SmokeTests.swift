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

@Test func bundleVersionComesFromMarketingVersion() {
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    #expect(short.wholeMatch(of: /\d+\.\d+\.\d+/) != nil, "CFBundleShortVersionString was '\(short)'")
    #expect(build.wholeMatch(of: /\d+/) != nil, "CFBundleVersion was '\(build)'")
}
