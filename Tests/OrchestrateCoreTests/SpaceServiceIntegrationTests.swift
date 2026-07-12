import XCTest

@testable import OrchestrateCore

/// Exercises the whole engine against real git, fully offline: a throwaway source
/// repo wired to a local bare "remote" in a temp dir. Nothing touches the user's
/// real repos, settings, or spaces registry.
final class SpaceServiceIntegrationTests: XCTestCase {
    private let shell = Shell.shared

    func testCreateBranchFromBaseThenDelete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchestrate-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Bare "remote".
        let remote = root.appendingPathComponent("remote.git")
        try shell.check("git", ["init", "--bare", "-b", "main", remote.path])

        // Source repo (the "project"), sibling-parent so the space lands in `parent`.
        let parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = parent.appendingPathComponent("proj")
        try git(["init", "-b", "main", source.path])
        try git(["config", "user.email", "test@example.com"], in: source)
        try git(["config", "user.name", "Test"], in: source)

        try write("main\n", to: source.appendingPathComponent("README.md"))
        try git(["add", "."], in: source)
        try git(["commit", "-m", "init"], in: source)
        try git(["remote", "add", "origin", remote.path], in: source)
        try git(["push", "-u", "origin", "main"], in: source)

        try git(["checkout", "-b", "base"], in: source)
        try write("base\n", to: source.appendingPathComponent("BASE.md"))
        try git(["add", "."], in: source)
        try git(["commit", "-m", "base"], in: source)
        try git(["push", "-u", "origin", "base"], in: source)
        try git(["checkout", "main"], in: source)

        // Create the space.
        let project = Project(name: "proj", path: source.path)
        let spacesURL = root.appendingPathComponent("spaces.yaml")
        let service = SpaceService()
        let space = try service.create(
            project: project, branchName: "feat/test", baseBranch: "base", spacesURL: spacesURL)

        let dest = parent.appendingPathComponent("proj__feature-feat-test")
        XCTAssertEqual(space.name, "proj__feature-feat-test")
        XCTAssertEqual(space.destination, dest.path)
        XCTAssertEqual(space.taskType, "feature")
        XCTAssertEqual(space.taskValue, "feat/test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))

        // Checked out onto the new branch…
        let current = try shell.check("git", ["branch", "--show-current"], cwd: dest)
        XCTAssertEqual(current, "feat/test")
        // …based on `base` (so BASE.md is present)…
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("BASE.md").path))
        // …with origin re-pointed at the real upstream.
        let originURL = try shell.check("git", ["remote", "get-url", "origin"], cwd: dest)
        XCTAssertEqual(originURL, remote.path)

        // Tracking entry written to the temp registry.
        var store = try SpaceStore.load(url: spacesURL)
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.spaces.first?.name, "proj__feature-feat-test")

        // Delete removes both the directory and the tracking entry.
        try service.delete(space, spacesURL: spacesURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        store = try SpaceStore.load(url: spacesURL)
        XCTAssertTrue(store.spaces.isEmpty)
    }

    // MARK: - Helpers

    private func git(_ args: [String], in dir: URL? = nil) throws {
        try shell.check("git", args, cwd: dir)
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
