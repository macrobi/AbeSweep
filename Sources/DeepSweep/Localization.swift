import Foundation

enum AppLanguage: String, Sendable {
    case hungarian = "hu"
    case english = "en"

    static let current: AppLanguage = {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }()

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        let preferred = preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("hu") ? .hungarian : .english
    }
}

enum L10n {
    static let language = AppLanguage.current
    static var isHungarian: Bool { language == .hungarian }

    static func text(_ hungarian: String, _ english: String) -> String {
        isHungarian ? hungarian : english
    }

    static func itemCount(_ count: Int) -> String {
        isHungarian ? "\(count) elem" : "\(count) item\(count == 1 ? "" : "s")"
    }

    static func selectedCount(_ count: Int) -> String {
        isHungarian ? "\(count) kijelölve" : "\(count) selected"
    }
}
