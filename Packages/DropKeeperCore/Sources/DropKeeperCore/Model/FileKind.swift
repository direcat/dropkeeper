import UniformTypeIdentifiers

public enum FileKind: String, Codable, Sendable, CaseIterable {
    case image, document, archive, installer, code, other

    private static let byExtension: [String: FileKind] = [
        "png": .image, "jpg": .image, "jpeg": .image, "heic": .image, "gif": .image, "webp": .image,
        "tiff": .image, "svg": .image,
        "pdf": .document, "doc": .document, "docx": .document, "pages": .document, "rtf": .document,
        "txt": .document, "md": .document, "xls": .document, "xlsx": .document, "numbers": .document,
        "key": .document, "ppt": .document, "pptx": .document, "csv": .document,
        "zip": .archive, "tar": .archive, "gz": .archive, "tgz": .archive, "bz2": .archive, "xz": .archive,
        "7z": .archive, "rar": .archive,
        "dmg": .installer, "pkg": .installer, "mpkg": .installer, "app": .installer, "iso": .installer,
        "swift": .code, "json": .code, "js": .code, "ts": .code, "py": .code, "rb": .code, "go": .code,
        "rs": .code, "c": .code, "h": .code, "m": .code, "cpp": .code, "java": .code, "kt": .code,
        "sh": .code, "yml": .code, "yaml": .code, "xml": .code, "html": .code, "css": .code, "sql": .code,
    ]

    public static func classify(pathExtension: String) -> FileKind {
        let ext = pathExtension.lowercased()
        if let kind = byExtension[ext] { return kind }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .text)
        {
            return .document
        }
        return .other
    }
}
