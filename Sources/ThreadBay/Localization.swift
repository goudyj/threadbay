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
    /// Translation bundles never change at runtime; resolve each `.lproj` once
    /// instead of on every string lookup (view bodies call this constantly).
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for language in AppLanguage.allCases where language != .system {
            let identifier = language.rawValue
            let resourceIdentifier = identifier == "zh-Hans" ? "zh-hans" : identifier
            if let path = Bundle.module.path(forResource: resourceIdentifier, ofType: "lproj"),
                let bundle = Bundle(path: path)
            {
                result[identifier] = bundle
            }
        }
        return result
    }()

    static func string(
        _ key: String,
        language: AppLanguage,
        arguments: [CVarArg] = []
    ) -> String {
        let identifier = language.resolvedIdentifier
        let bundle = Self.bundles[identifier] ?? Bundle.module

        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: identifier),
            arguments: arguments)
    }
}
