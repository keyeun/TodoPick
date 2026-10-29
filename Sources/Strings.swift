import Foundation

/// UI language. Chosen at install (`./build.sh install --lang en`) or from the menu bar.
enum AppLanguage: String, CaseIterable {
    case ko, en

    static let defaultsKey = "language"

    /// Saved choice, else the Mac's preferred language (Korean if it starts with "ko", otherwise English).
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .ko : .en
    }

    var displayName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        }
    }
}

/// Picks the Korean or English text for the current UI language.
func L(_ ko: String, _ en: String) -> String {
    AppLanguage.current == .ko ? ko : en
}
