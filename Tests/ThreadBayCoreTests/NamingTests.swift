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

    func testBranchSpaceNameHasNoTaskPrefix() {
        XCTAssertEqual(
            Naming.branchSpaceName(project: "proj", branch: "feat/x"),
            "proj__feat-x")
    }

    func testPullRequestSpaceName() {
        XCTAssertEqual(Naming.pullRequestSpaceName(project: "proj", number: 42), "proj__pr-42")
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
