import Foundation

/// The app's display language, backed by the `AppleLanguages` user default.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    private static let key = "AppleLanguages"

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static var current: AppLanguage {
        guard
            let languages = UserDefaults.standard.array(forKey: key) as? [String],
            let first = languages.first
        else { return .system }
        if first.hasPrefix("zh-Hans") { return .simplifiedChinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// Persists the language; takes effect after relaunch.
    func apply() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: Self.key)
        case .english, .simplifiedChinese:
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }
}
