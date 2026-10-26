import Foundation

/// Finds a file in the same folder that holds exactly the same bytes as a new one.
///
/// Two steps so the engine can keep the cheap one on its actor and run the expensive one elsewhere:
/// `candidates` only lists names and sizes, `firstMatch` reads file contents.
public enum DuplicateFinder {
    /// Direct children of `folderPath` (sorted by name) of the same non-zero size as `path`'s.
    /// Skips `path` itself and names the detector never tracks; uses a plain size lookup only.
    public static func candidates(
        path: String, size: Int64, folderPath: String, ignoredPatterns: [String], fs: any FileSystem
    ) -> [String] {
        guard size > 0, let names = try? fs.contentsOfDirectory(folderPath) else { return [] }
        return names.sorted().filter { name in
            let candidate = folderPath + "/" + name
            return candidate != path
                && DownloadDetector.isEligibleName(name, ignoredPatterns: ignoredPatterns)
                && fs.fileSize(candidate) == size
        }
    }

    /// Display name of the first candidate whose content equals `path`'s. Reads files: run it off the engine actor.
    public static func firstMatch(
        path: String, candidates: [String], folderPath: String, fs: any FileSystem
    ) -> String? {
        candidates.first { fs.contentsEqual(path, folderPath + "/" + $0) }
    }

    /// Both steps in one call.
    public static func find(
        path: String, size: Int64, folderPath: String, ignoredPatterns: [String], fs: any FileSystem
    ) -> String? {
        firstMatch(
            path: path,
            candidates: candidates(
                path: path, size: size, folderPath: folderPath, ignoredPatterns: ignoredPatterns, fs: fs),
            folderPath: folderPath, fs: fs)
    }
}
