import Foundation

/// The app's language override. macOS reads the `AppleLanguages` default once at launch to pick the app's
/// localization, so a change only takes effect after a restart. "System" removes the override.
/// `UserDefaults` is thread-safe, hence `@unchecked Sendable`.
struct AppLanguage: @unchecked Sendable {
    /// Localizations the app ships, as listed in `CFBundleLocalizations`.
    static let supported = ["en", "cs", "de", "es", "fr"]

    /// Created at launch (see `AppDelegate`), so `launchedWith` is the language the running app uses.
    static let shared = AppLanguage()

    private let defaults: UserDefaults
    private let domain: String
    private let key = "AppleLanguages"
    /// The language the app launched with: the override at creation time, or `nil` for the system language.
    let launchedWith: String?

    /// `domain` is the persistent domain that holds the override. Tests pass an injected suite and its name.
    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "") {
        self.defaults = defaults
        self.domain = domain
        launchedWith = Self.override(in: defaults, domain: domain)
    }

    /// The chosen language code, or `nil` when the app follows the system.
    var selection: String? { Self.override(in: defaults, domain: domain) }

    /// Whether the selection differs from what the running app launched with.
    var needsRestart: Bool { selection != launchedWith }

    func select(_ code: String?) {
        guard let code, Self.supported.contains(code) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set([code], forKey: key)
    }

    /// Reads the app's own domain only: `array(forKey:)` would also return the system-wide list.
    private static func override(in defaults: UserDefaults, domain: String) -> String? {
        guard let list = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
            let first = list.first, supported.contains(first)
        else { return nil }
        return first
    }
}
