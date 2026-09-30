import Foundation

/// Deadline rules for active records.
public enum Scheduler {
    public static func deadline(for file: TrackedFile, settings: Settings) -> Date? {
        switch file.state {
        case .pending: return file.firstSeen.addingTimeInterval(settings.gracePeriod)
        case .scheduled: return file.expiresAt
        case .kept, .trashed, .gone, .failed: return nil
        }
    }

    public static func nextDeadline(in files: [TrackedFile], settings: Settings) -> Date? {
        files.compactMap { deadline(for: $0, settings: settings) }.min()
    }
}
