import Foundation
import Testing

@testable import DropKeeperCore

@Suite struct EngineFileUpdatesTests {
    @Test func fileUpdatesYieldsInitialValueAndChanges() async throws {
        let harness = try EngineHarness()
        try await harness.startWithDownloads()
        var updates = harness.engine.fileUpdates(in: [.pending]).makeAsyncIterator()
        #expect(try await updates.next() == [])
        _ = await harness.drop("a.pdf")
        var latest: [TrackedFile]? = []
        while let files = latest, files.isEmpty {
            latest = try await updates.next()
        }
        #expect(latest?.map(\.displayName) == ["a.pdf"])
    }
}
