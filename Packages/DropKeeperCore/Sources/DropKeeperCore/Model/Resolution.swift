import GRDB

/// How a record that is no longer active came to be finished. nil on active records and on history from
/// before 1.2.
public enum Resolution: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case userKept, defaultKept, restored, expired, deletedNow, movedOut, folderRemoved, removedOutside, reappeared

    /// True when the user, a timer or the default settings decided the outcome; false when the file was
    /// merely moved, removed or put back outside the app's control.
    public var isDecision: Bool {
        switch self {
        case .userKept, .defaultKept, .restored, .expired, .deletedNow: true
        case .movedOut, .folderRemoved, .removedOutside, .reappeared: false
        }
    }

    /// Raw values of the decision cases, for SQL `IN` clauses.
    public static let decisionValues: [String] = allCases.filter(\.isDecision).map(\.rawValue)
}
