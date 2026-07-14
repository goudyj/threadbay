import Foundation
import XCTest

@testable import ThreadBayCore

final class AppEnvironmentTests: XCTestCase {
    func testUnknownEnvironmentDefaultsToProduction() {
        XCTAssertEqual(AppEnvironment.resolve(nil), .production)
        XCTAssertEqual(AppEnvironment.resolve("unknown"), .production)
    }

    func testDevelopmentEnvironmentIsResolvedFromBundleValue() {
        XCTAssertEqual(AppEnvironment.resolve("development"), .development)
    }

    func testDevelopmentPathsAreIsolatedFromProduction() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let applicationSupport = home.appendingPathComponent(
            "Library/Application Support", isDirectory: true)

        let production = Paths.locations(
            environment: .production,
            home: home,
            applicationSupport: applicationSupport)
        let development = Paths.locations(
            environment: .development,
            home: home,
            applicationSupport: applicationSupport)

        XCTAssertEqual(
            production.settingsFile.path,
            "/Users/test/Library/Application Support/com.jlex.threadbay/settings.yaml")
        XCTAssertEqual(production.spacesFile.path, "/Users/test/.threadbay/spaces.yaml")
        XCTAssertEqual(
            development.settingsFile.path,
            "/Users/test/Library/Application Support/com.jlex.threadbay.dev/settings.yaml")
        XCTAssertEqual(development.spacesFile.path, "/Users/test/.threadbay-dev/spaces.yaml")
        XCTAssertNotEqual(production.agentsFile, development.agentsFile)
        XCTAssertNotEqual(production.eventSocket, development.eventSocket)
    }
}
