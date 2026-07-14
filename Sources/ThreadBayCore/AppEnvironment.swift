import Foundation

/// Runtime profile embedded in the app bundle by the build script.
public enum AppEnvironment: String, Sendable {
    case production
    case development

    public static var current: AppEnvironment {
        resolve(Bundle.main.object(forInfoDictionaryKey: "ThreadBayEnvironment"))
    }

    public var displayName: String {
        switch self {
        case .production: return "ThreadBay"
        case .development: return "ThreadBay Dev"
        }
    }

    static func resolve(_ value: Any?) -> AppEnvironment {
        guard let rawValue = value as? String else { return .production }
        return AppEnvironment(rawValue: rawValue) ?? .production
    }

    var appDirectoryName: String {
        switch self {
        case .production: return "com.jlex.threadbay"
        case .development: return "com.jlex.threadbay.dev"
        }
    }

    var spacesDirectoryName: String {
        switch self {
        case .production: return ".threadbay"
        case .development: return ".threadbay-dev"
        }
    }
}
