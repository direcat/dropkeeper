import Foundation
import UniformTypeIdentifiers

public enum RuleMatcher {
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// The first enabled rule whose folder is nil or `folderPath` and whose match hits the file.
    public static func firstMatch(
        name: String, path: String, folderPath: String, rules: [Rule], fs: any FileSystem
    ) -> Rule? {
        rules.first { rule in
            guard rule.isEnabled, rule.folderPath == nil || rule.folderPath == folderPath else { return false }
            switch rule.match {
            case .pattern(let pattern): return IgnorePattern.matches(name: name, pattern: pattern)
            case .category(let category): return matches(category, name: name, path: path, fs: fs)
            }
        }
    }

    private static func matches(_ category: RuleCategory, name: String, path: String, fs: any FileSystem) -> Bool {
        if category == .screenshots {
            // Screen recordings carry the same attribute; only images are screenshots.
            let ext = (name as NSString).pathExtension
            return fs.hasXattr(screenCaptureAttribute, at: path)
                && UTType(filenameExtension: ext)?.conforms(to: .image) == true
        }
        // `.tar.gz` and friends: the last extension decides.
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        switch category {
        case .installers: return isInstaller(type)
        case .images: return type.conforms(to: .image)
        case .archives: return type.conforms(to: .archive) && !isInstaller(type)
        case .invitationsAndContacts: return type.conforms(to: .calendarEvent) || type.conforms(to: .vCard)
        case .screenshots: return false
        }
    }

    private static func isInstaller(_ type: UTType) -> Bool {
        type.conforms(to: .diskImage) || type.conforms(to: UTType("com.apple.installer-package-archive")!)
    }
}
