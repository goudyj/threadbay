import XCTest

@testable import ThreadBay

@MainActor
final class TerminalFontSettingsTests: XCTestCase {
    func testDefaultsToMenloThirteenPoints() {
        let settings = TerminalFontSettings()

        XCTAssertEqual(settings.family, "Menlo")
        XCTAssertEqual(settings.size, 13)
        XCTAssertEqual(settings.font.familyName, "Menlo")
        XCTAssertEqual(settings.font.pointSize, 13)
    }

    func testUnavailableFontFallsBackToMenloAndSizeIsClamped() {
        let tooSmall = TerminalFontSettings(family: "Missing Font", size: 1)
        let tooLarge = TerminalFontSettings(size: 100)

        XCTAssertEqual(tooSmall.family, "Menlo")
        XCTAssertEqual(tooSmall.size, TerminalFontSettings.sizeRange.lowerBound)
        XCTAssertEqual(tooLarge.size, TerminalFontSettings.sizeRange.upperBound)
    }

    func testRoundTripsThroughUserDefaults() throws {
        let suiteName = "TerminalFontSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TerminalFontSettings(family: "Monaco", size: 17)

        settings.save(to: defaults)

        XCTAssertEqual(TerminalFontSettings.load(from: defaults), settings)
    }
}
