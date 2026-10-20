import Testing

@testable import DropKeeperCore

@Test func packageBuilds() {
    #expect(DropKeeperCoreInfo.version == "1.0.2")
}
