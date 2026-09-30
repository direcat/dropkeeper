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
