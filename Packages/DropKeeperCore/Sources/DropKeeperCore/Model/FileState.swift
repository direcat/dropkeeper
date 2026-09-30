public enum FileState: String, Codable, Sendable, CaseIterable {
    case pending, scheduled, kept, trashed, gone, failed

    /// Active records have a pending deadline and are processed by the scheduler.
    public var isActive: Bool { self == .pending || self == .scheduled }
}
