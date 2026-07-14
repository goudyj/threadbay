import XCTest

@testable import ThreadBayCore

final class NamingTests: XCTestCase {
    func testSlugifyLowercasesAndReplaces() {
        XCTAssertEqual(Naming.slugify("feat/Login_Flow"), "feat-login-flow")
    }

    func testSlugifyCollapsesRunsAndTrims() {
        XCTAssertEqual(Naming.slugify("--feat//a__b -- c--"), "feat-a-b-c")
    }

    func testSlugifyDropsNonAscii() {
        // 'é' is dropped, the rest is kept and lowercased.
        XCTAssertEqual(Naming.slugify("Héllo"), "hllo")
    }

    func testRandomSpaceNameUsesProjectAndTwoWordIdentity() {
        let name = Naming.randomSpaceName(project: "My Project")
        XCTAssertTrue(name.hasPrefix("my-project__"), name)
        let components = name.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2)
        XCTAssertEqual(components.last?.split(separator: "-").count, 2)
    }

    func testGeneratedTitleOmitsProjectPrefix() {
        let space = TrackedSpace(
            projectName: "project", destination: "/tmp/project__cosmic-otter",
            name: "project__cosmic-otter", createdAt: "2026-07-10T12:34:56Z",
            taskType: "feature", taskValue: "feat/x")
        XCTAssertEqual(space.displayTitle, "cosmic-otter")
    }

    func testEnsureUniqueNameAppendsSuffix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(Naming.ensureUniqueName(parent: dir, base: "space"), "space")

        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("space"), withIntermediateDirectories: true)
        XCTAssertEqual(Naming.ensureUniqueName(parent: dir, base: "space"), "space-2")

        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("space-2"), withIntermediateDirectories: true)
        XCTAssertEqual(Naming.ensureUniqueName(parent: dir, base: "space"), "space-3")
    }
}
