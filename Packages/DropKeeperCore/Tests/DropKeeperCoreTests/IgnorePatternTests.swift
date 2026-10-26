import Testing

@testable import DropKeeperCore

@Test func patternNormalization() {
    #expect(IgnorePattern.normalize(" ZIP ") == "*.zip")  // bare word → extension pattern
    #expect(IgnorePattern.normalize(".dmg") == "*.dmg")
    #expect(IgnorePattern.normalize("~$*") == "~$*")
    #expect(IgnorePattern.normalize("Report*.PDF") == "report*.pdf")
    #expect(IgnorePattern.normalize("  ") == nil)
}

@Test func patternMatchingIsCaseInsensitiveOnNameOnly() {
    #expect(IgnorePattern.matches(name: "~$dlaha.docx", pattern: "~$*"))
    #expect(IgnorePattern.matches(name: "#notes.txt#", pattern: "#*#"))
    #expect(IgnorePattern.matches(name: "draft.md~", pattern: "*~"))
    #expect(IgnorePattern.matches(name: "Setup.DMG", pattern: "*.dmg"))
    #expect(!IgnorePattern.matches(name: "report.pdf", pattern: "~$*"))
}

@Test func isIgnoredChecksAnyPattern() {
    #expect(IgnorePattern.isIgnored(name: "a.zip", patterns: ["*.dmg", "*.zip"]))
    #expect(!IgnorePattern.isIgnored(name: "a.pdf", patterns: ["*.dmg", "*.zip"]))
    #expect(!IgnorePattern.isIgnored(name: "a.pdf", patterns: []))
}
