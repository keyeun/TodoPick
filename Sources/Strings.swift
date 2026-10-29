import SwiftUI

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

/// Lets `Tools/Gifs.swift` pre-fill text fields while recording demos. The app never sets it.
struct DemoInput {
    var inbox: String? = nil
    var deadline: String? = nil
}

private struct DemoInputKey: EnvironmentKey {
    static let defaultValue = DemoInput()
}

extension EnvironmentValues {
    var demoInput: DemoInput {
        get { self[DemoInputKey.self] }
        set { self[DemoInputKey.self] = newValue }
    }
}

/// What a text field looks like mid-typing in a demo: the text plus a caret.
struct DemoTypedText: View {
    var text: String
    var font: Font
    var body: some View {
        (Text(text) + Text("|").foregroundColor(Pal.coral))
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Picks the Korean or English text for the current UI language.
func L(_ ko: String, _ en: String) -> String {
    AppLanguage.current == .ko ? ko : en
}
