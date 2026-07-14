import XCTest

@testable import Orchestrate

final class LocalizationTests: XCTestCase {
    func testSystemLanguageSelectsSupportedOSLanguage() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), "fr")
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["es-ES"]), "es")
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hant"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["de-DE"]), "en")
    }

    func testEveryLanguageLoadsItsTranslationBundle() {
        XCTAssertEqual(L10n.string("new_space.title", language: .english), "New Space")
        XCTAssertEqual(L10n.string("new_space.title", language: .french), "Nouvel espace")
        XCTAssertEqual(L10n.string("new_space.title", language: .spanish), "Nuevo espacio")
        XCTAssertEqual(L10n.string("new_space.title", language: .simplifiedChinese), "新建空间")
    }

    func testLocalizedFormattingUsesArguments() {
        XCTAssertEqual(
            L10n.string(
                "branch.remote",
                language: .english,
                arguments: ["origin/feat/search"]),
            "origin/feat/search — remote")
    }
}
