import Testing

@testable import DropKeeperCore

@Test(arguments: [
    ("png", FileKind.image), ("JPG", .image), ("heic", .image), ("webp", .image),
    ("pdf", .document), ("docx", .document), ("pages", .document),
    ("zip", .archive), ("7z", .archive), ("gz", .archive), ("tar", .archive),
    ("dmg", .installer), ("pkg", .installer), ("app", .installer),
    ("swift", .code), ("json", .code), ("py", .code), ("js", .code),
    ("xyz123", .other), ("", .other),
])
func classifiesExtension(ext: String, expected: FileKind) {
    #expect(FileKind.classify(pathExtension: ext) == expected)
}

@Test func onlyPendingAndScheduledAreActive() {
    #expect(FileState.allCases.filter(\.isActive) == [.pending, .scheduled])
}
