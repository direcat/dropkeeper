import Foundation
import Testing

@testable import DropKeeper

private func makeDefaults() -> (UserDefaults, String) {
    let name = "net.direcat.dropkeeper.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

@Test func followsTheSystemByDefault() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let language = AppLanguage(defaults: defaults, domain: name)
    #expect(language.selection == nil)
    #expect(language.launchedWith == nil)
    #expect(!language.needsRestart)
}

@Test func selectingStoresTheOverrideAndNeedsARestart() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let language = AppLanguage(defaults: defaults, domain: name)
    language.select("de")
    #expect(language.selection == "de")
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["de"])
    #expect(language.needsRestart)
    language.select(nil)
    #expect(language.selection == nil)
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    #expect(!language.needsRestart)
}

@Test func launchLanguageComesFromTheStoredOverride() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["cs"], forKey: "AppleLanguages")
    let language = AppLanguage(defaults: defaults, domain: name)
    #expect(language.launchedWith == "cs")
    #expect(!language.needsRestart)
    language.select("fr")
    #expect(language.needsRestart)
    language.select("cs")
    #expect(!language.needsRestart)
    language.select(nil)
    #expect(language.needsRestart)
}

@Test func unsupportedCodesClearTheOverride() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["xx"], forKey: "AppleLanguages")
    let language = AppLanguage(defaults: defaults, domain: name)
    #expect(language.selection == nil)
    language.select("de")
    language.select("xx")
    #expect(language.selection == nil)
}

@Test func regionTaggedCodesFromSystemSettingsAreNormalized() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["de-DE"], forKey: "AppleLanguages")
    let language = AppLanguage(defaults: defaults, domain: name)
    #expect(language.selection == "de")
    #expect(language.launchedWith == "de")
    #expect(!language.needsRestart)
    language.select("de")
    #expect(!language.needsRestart)
}

@Test func onlyTheFirstPreferredLanguageCounts() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["en-US", "cs-CZ"], forKey: "AppleLanguages")
    let language = AppLanguage(defaults: defaults, domain: name)
    #expect(language.selection == "en")
    #expect(!language.needsRestart)
}

@Test func supportedLanguagesMatchTheBundle() {
    let declared = Bundle.main.infoDictionary?["CFBundleLocalizations"] as? [String]
    if let declared { #expect(Set(declared) == Set(AppLanguage.supported)) }
}
