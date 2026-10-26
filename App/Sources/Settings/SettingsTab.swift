import Foundation

/// The Settings window's tabs, in toolbar order.
enum SettingsTab: String, CaseIterable {
    case general, folders, expiry, rules, data, about

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .folders: String(localized: "Folders", comment: "Settings tab title: the watched folders")
        case .expiry: String(localized: "Expiry")
        case .rules: String(localized: "Rules", comment: "Settings tab title: which downloads DropKeeper handles")
        case .data: String(localized: "Data")
        case .about: String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .folders: "folder"
        case .expiry: "timer"
        case .rules: "list.bullet.rectangle"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
}
