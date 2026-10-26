import Foundation

public enum DownloadDetector {
    public static let partialExtensions: Set<String> = [
        "crdownload", "part", "download", "opdownload", "partial", "tmp",
    ]
    static let ignoredNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    /// True when `path` is a direct child of `folderPath` that could be a finished download.
    public static func isCandidate(path: String, folderPath: String, ignoredPatterns: [String]) -> Bool {
        guard (path as NSString).deletingLastPathComponent == folderPath else { return false }
        return isEligibleName((path as NSString).lastPathComponent, ignoredPatterns: ignoredPatterns)
    }

    /// The name-only part of `isCandidate`, shared with `DuplicateFinder` so both skip the same files.
    static func isEligibleName(_ name: String, ignoredPatterns: [String]) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."), !ignoredNames.contains(name) else { return false }
        guard !IgnorePattern.isIgnored(name: name, patterns: ignoredPatterns) else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return !partialExtensions.contains(ext)
    }
}
