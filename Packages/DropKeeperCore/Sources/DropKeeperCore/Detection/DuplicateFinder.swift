import Foundation

/// Finds a file in the same folder that holds exactly the same bytes as a new one.
public enum DuplicateFinder {
    /// Display name of the first direct child of `folderPath` (sorted by name) that matches `path`'s content.
    /// Skips `path` itself, dotfiles, directories and ignored names; empty files never count as duplicates.
    public static func find(
        path: String, size: Int64, folderPath: String, ignoredPatterns: [String], fs: any FileSystem
    ) -> String? {
        guard size > 0, let names = try? fs.contentsOfDirectory(folderPath) else { return nil }
        for name in names.sorted() {
            let candidate = folderPath + "/" + name
            guard candidate != path, !name.hasPrefix("."),
                !IgnorePattern.isIgnored(name: name, patterns: ignoredPatterns),
                let stat = fs.stat(candidate), !stat.isDirectory, stat.size == size,
                fs.contentsEqual(path, candidate)
            else { continue }
            return name
        }
        return nil
    }
}
