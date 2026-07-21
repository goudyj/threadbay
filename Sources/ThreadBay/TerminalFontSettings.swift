import AppKit
import Foundation

struct TerminalFontSettings: Equatable {
    static let defaultFamily = "Menlo"
    static let defaultSize = 13.0
    static let sizeRange = 9.0...24.0

    private static let familyKey = "terminalFontFamily"
    private static let sizeKey = "terminalFontSize"

    let family: String
    let size: Double

    init(family: String = defaultFamily, size: Double = defaultSize) {
        self.family = Self.isAvailableMonospacedFont(family) ? family : Self.defaultFamily
        self.size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    var font: NSFont {
        NSFont(name: family, size: CGFloat(size))
            ?? NSFont(name: Self.defaultFamily, size: CGFloat(size))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    static var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter(isAvailableMonospacedFont)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let family = defaults.string(forKey: familyKey) ?? defaultFamily
        let size = defaults.object(forKey: sizeKey) == nil
            ? defaultSize
            : defaults.double(forKey: sizeKey)
        return Self(family: family, size: size)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(family, forKey: Self.familyKey)
        defaults.set(size, forKey: Self.sizeKey)
    }

    private static func isAvailableMonospacedFont(_ family: String) -> Bool {
        NSFont(name: family, size: CGFloat(defaultSize))?.isFixedPitch == true
    }
}
