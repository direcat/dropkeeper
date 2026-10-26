import Testing

@testable import DropKeeperCore

private let folder = "/fake/D"

@Test(arguments: [
    ("/fake/D/report.pdf", true),
    ("/fake/D/Folder", true),
    ("/fake/D/noext", true),
    ("/fake/D/sub/report.pdf", false),  // not a direct child
    ("/fake/Other/report.pdf", false),
    ("/fake/D/.hidden", false),
    ("/fake/D/.DS_Store", false),
    ("/fake/D/.localized", false),
    ("/fake/D/Unconfirmed 1.crdownload", false),
    ("/fake/D/file.zip.part", false),
    ("/fake/D/file.pdf.download", false),
    ("/fake/D/file.opdownload", false),
    ("/fake/D/file.partial", false),
    ("/fake/D/file.tmp", false),
    ("/fake/D/installer.dmg", false),  // ignored by settings below
    ("/fake/D/Installer.PKG", false),
])
func candidateRules(path: String, expected: Bool) {
    #expect(
        DownloadDetector.isCandidate(path: path, folderPath: folder, ignoredPatterns: ["*.dmg", "*.pkg"])
            == expected)
}

@Test func detectorSkipsOfficeOwnerFile() {
    let defaults = IgnorePattern.defaults
    #expect(!DownloadDetector.isCandidate(path: "/d/~$x.docx", folderPath: "/d", ignoredPatterns: defaults))
    #expect(DownloadDetector.isCandidate(path: "/d/x.docx", folderPath: "/d", ignoredPatterns: defaults))
}
