import Foundation

/// Case-insensitive shell-style patterns (`fnmatch`) matched against a file name only.
public enum IgnorePattern {
    /// Editor and Office scratch files, ignored on a new install.
    public static let defaults = ["~$*", "#*#", "*~"]

    /// Trims, lowercases and expands a bare word or `.ext` into `*.ext`; nil when nothing is left.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let rest = String(trimmed.drop { $0 == "." })
        guard !rest.isEmpty else { return nil }
        let hasGlob = rest.contains { "*?[".contains($0) }
        if hasGlob { return trimmed }
        if trimmed.hasPrefix(".") || !rest.contains(".") { return "*.\(rest)" }
        return rest
    }

    public static func matches(name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, FNM_CASEFOLD) == 0
    }

    public static func isIgnored(name: String, patterns: [String]) -> Bool {
        patterns.contains { matches(name: name, pattern: $0) }
    }
}
