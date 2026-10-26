import Foundation

public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case installers, images, archives, invitationsAndContacts, screenshots
}

public enum RuleMatch: Codable, Sendable, Equatable {
    case category(RuleCategory)
    /// A file-name pattern, see `IgnorePattern`.
    case pattern(String)
}

/// Schedules matching new files for removal without asking.
public struct Rule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var match: RuleMatch
    /// Absolute path of the watched folder the rule applies to; nil means every watched folder.
    public var folderPath: String?
    public var duration: TimeInterval
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), name: String, match: RuleMatch, folderPath: String? = nil, duration: TimeInterval,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.match = match
        self.folderPath = folderPath
        self.duration = duration
        self.isEnabled = isEnabled
    }

    /// The suggested rules, shipped disabled so nothing is scheduled until the user opts in.
    /// Order matters (first match wins): Screenshots comes before Images so it is not shadowed for PNGs.
    public static func defaults(home: String) -> [Rule] {
        [
            Rule(
                id: UUID(uuidString: "6F1D0A10-0001-4C5E-9A10-D40F7E000001")!, name: "Installers",
                match: .category(.installers), duration: 86_400, isEnabled: false),
            Rule(
                id: UUID(uuidString: "6F1D0A10-0005-4C5E-9A10-D40F7E000005")!, name: "Screenshots on Desktop",
                match: .category(.screenshots), folderPath: home + "/Desktop", duration: 86_400,
                isEnabled: false),
            Rule(
                id: UUID(uuidString: "6F1D0A10-0002-4C5E-9A10-D40F7E000002")!, name: "Images",
                match: .category(.images), duration: 3600, isEnabled: false),
            Rule(
                id: UUID(uuidString: "6F1D0A10-0003-4C5E-9A10-D40F7E000003")!, name: "Archives",
                match: .category(.archives), duration: 86_400, isEnabled: false),
            Rule(
                id: UUID(uuidString: "6F1D0A10-0004-4C5E-9A10-D40F7E000004")!, name: "Invitations & contacts",
                match: .category(.invitationsAndContacts), duration: 1800, isEnabled: false),
        ]
    }
}

/// A rule that scheduled a new file; reported to the UI in one batch per poll.
public struct RuleApplication: Sendable, Equatable, Identifiable {
    public let file: TrackedFile
    public let ruleId: UUID
    public let ruleName: String
    public var id: FileID { file.id }

    public init(file: TrackedFile, ruleId: UUID, ruleName: String) {
        self.file = file
        self.ruleId = ruleId
        self.ruleName = ruleName
    }
}
