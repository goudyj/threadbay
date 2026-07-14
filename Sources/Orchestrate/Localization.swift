import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    var locale: Locale {
        Locale(identifier: resolvedIdentifier)
    }

    var resolvedIdentifier: String {
        switch self {
        case .system:
            return Self.resolve(preferredLanguages: Locale.preferredLanguages)
        default:
            return rawValue
        }
    }

    static func resolve(preferredLanguages: [String]) -> String {
        for identifier in preferredLanguages {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("fr") { return "fr" }
            if normalized.hasPrefix("es") { return "es" }
            if normalized.hasPrefix("zh") { return "zh-Hans" }
            if normalized.hasPrefix("en") { return "en" }
        }
        return "en"
    }
}

enum L10n {
    static func string(
        _ key: String,
        language: AppLanguage,
        arguments: [CVarArg] = []
    ) -> String {
        let identifier = language.resolvedIdentifier
        let resourceIdentifier = identifier == "zh-Hans" ? "zh-hans" : identifier
        let bundle: Bundle
        if let path = Bundle.module.path(forResource: resourceIdentifier, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        {
            bundle = localizedBundle
        } else {
            bundle = Bundle.module
        }

        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: identifier),
            arguments: arguments)
    }
}
