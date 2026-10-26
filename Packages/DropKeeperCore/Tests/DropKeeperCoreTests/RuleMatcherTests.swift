import Foundation
import Testing
import UniformTypeIdentifiers

@testable import DropKeeperCore

struct RuleMatcherTests {
    let fs = FakeFileSystem()
    let folder = "/watched"

    init() {
        fs.mkdir(folder)
    }

    private func rule(
        _ name: String, _ match: RuleMatch, folder: String? = nil, enabled: Bool = true
    ) -> Rule {
        Rule(name: name, match: match, folderPath: folder, duration: 3600, isEnabled: enabled)
    }

    private func match(_ name: String, rules: [Rule], in folderPath: String? = nil) -> String? {
        let folderPath = folderPath ?? folder
        let path = folderPath + "/" + name
        if !fs.exists(path) { fs.createFile(path, added: nil) }
        return RuleMatcher.firstMatch(name: name, path: path, folderPath: folderPath, rules: rules, fs: fs)?.name
    }

    @Test func archivesExcludeInstallers() {
        let rules = [rule("Archives", .category(.archives)), rule("Installers", .category(.installers))]
        #expect(match("Setup.dmg", rules: rules) == "Installers")
        #expect(match("Setup.pkg", rules: rules) == "Installers")
        #expect(match("data.zip", rules: rules) == "Archives")
        #expect(match("data.tar.gz", rules: rules) == "Archives")
    }

    @Test func imagesCoverHeicAndWebp() {
        let rules = [rule("Images", .category(.images))]
        for name in ["a.png", "b.jpg", "c.heic", "d.webp", "E.PNG"] {
            #expect(match(name, rules: rules) == "Images", "\(name)")
        }
        #expect(match("doc.pdf", rules: rules) == nil)
    }

    @Test func invitationsAndContactsCoverIcsAndVcf() {
        let rules = [rule("Invites", .category(.invitationsAndContacts))]
        #expect(match("meeting.ics", rules: rules) == "Invites")
        #expect(match("person.vcf", rules: rules) == "Invites")
    }

    @Test func disabledRulesNeverMatch() {
        #expect(match("a.png", rules: [rule("Images", .category(.images), enabled: false)]) == nil)
    }

    @Test func folderSpecificRuleOnlyInThatFolder() {
        fs.mkdir("/other")
        let rules = [rule("Images here", .category(.images), folder: folder)]
        #expect(match("a.png", rules: rules) == "Images here")
        #expect(match("a.png", rules: rules, in: "/other") == nil)
    }

    @Test func screenshotDetectedByXattr() throws {
        let rules = [rule("Shots", .category(.screenshots))]
        fs.createFile(folder + "/Screenshot.png", added: nil)
        #expect(match("Screenshot.png", rules: rules) == nil)
        try fs.writeXattr("com.apple.metadata:kMDItemIsScreenCapture", value: "1", at: folder + "/Screenshot.png")
        #expect(match("Screenshot.png", rules: rules) == "Shots")
    }

    @Test func firstEnabledMatchWins() {
        let rules = [
            rule("Off", .category(.images), enabled: false), rule("First", .category(.images)),
            rule("Second", .category(.images)),
        ]
        #expect(match("a.png", rules: rules) == "First")
    }

    @Test func patternRule() {
        let rules = [rule("Calendar", .pattern("*.ics"))]
        #expect(match("Invite.ICS", rules: rules) == "Calendar")
        #expect(match("invite.txt", rules: rules) == nil)
    }

    @Test func installerTypeIdentifiersExistOnThisSystem() throws {
        #expect(UTType(filenameExtension: "dmg")?.conforms(to: .diskImage) == true)
        let pkg = try #require(UTType(filenameExtension: "pkg"))
        #expect(pkg.conforms(to: try #require(UTType("com.apple.installer-package-archive"))))
        #expect(UTType(filenameExtension: "gz")?.conforms(to: .archive) == true)
    }
}
