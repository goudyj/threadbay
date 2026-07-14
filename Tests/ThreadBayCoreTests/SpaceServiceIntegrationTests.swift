import XCTest

@testable import ThreadBayCore

/// Exercises the whole engine against real git, fully offline: a throwaway source
/// repo wired to a local bare "remote" in a temp dir. Nothing touches the user's
/// real repos, settings, or spaces registry.
final class SpaceServiceIntegrationTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let parent: URL
        let source: URL
        let remote: URL
        let spacesURL: URL
    }

    private let shell = Shell.shared

    func testCreateBranchFromRemoteBaseThenDelete() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try git(["checkout", "-b", "base"], in: fixture.source)
        try commitFile("base\n", named: "BASE.md", message: "base", in: fixture.source)
        try git(["push", "-u", "origin", "base"], in: fixture.source)
        try git(["checkout", "main"], in: fixture.source)
        try git(["branch", "-D", "base"], in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .feature(
                branchName: "feat/test",
                base: GitBranch(name: "base", location: .remote("origin"))),
            spacesURL: fixture.spacesURL)

        let dest = fixture.parent.appendingPathComponent("proj__feat-test")
        XCTAssertEqual(space.name, "proj__feat-test")
        XCTAssertEqual(space.destination, dest.path)
        XCTAssertEqual(space.taskType, "feature")
        XCTAssertEqual(space.taskValue, "feat/test")
        XCTAssertEqual(try currentBranch(in: dest), "feat/test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("BASE.md").path))
        XCTAssertEqual(
            try shell.check("git", ["remote", "get-url", "origin"], cwd: dest),
            fixture.remote.path)

        var store = try SpaceStore.load(url: fixture.spacesURL)
        XCTAssertEqual(store.spaces.map(\.name), ["proj__feat-test"])

        try SpaceService().delete(space, spacesURL: fixture.spacesURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        store = try SpaceStore.load(url: fixture.spacesURL)
        XCTAssertTrue(store.spaces.isEmpty)
    }

    func testCreateFromLocalOnlyBranchPreservesUnpushedCommit() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try git(["checkout", "-b", "local-only"], in: fixture.source)
        try commitFile("local\n", named: "LOCAL.md", message: "local", in: fixture.source)
        try git(["checkout", "main"], in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .existingBranch(GitBranch(name: "local-only", location: .local)),
            spacesURL: fixture.spacesURL)
        let dest = URL(fileURLWithPath: space.destination)

        XCTAssertEqual(space.name, "proj__local-only")
        XCTAssertEqual(space.taskType, "review")
        XCTAssertEqual(space.taskValue, "branch-local-only")
        XCTAssertEqual(try currentBranch(in: dest), "local-only")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("LOCAL.md").path))
    }

    func testCreateFromRemoteOnlyBranchTracksSelectedRemote() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try git(["checkout", "-b", "remote-only"], in: fixture.source)
        try commitFile("remote\n", named: "REMOTE.md", message: "remote", in: fixture.source)
        try git(["push", "-u", "origin", "remote-only"], in: fixture.source)
        try git(["checkout", "main"], in: fixture.source)
        try git(["branch", "-D", "remote-only"], in: fixture.source)

        let listed = try GitService().listBranches(repo: fixture.source)
        XCTAssertTrue(listed.contains(GitBranch(name: "main", location: .local)))
        XCTAssertTrue(listed.contains(GitBranch(name: "remote-only", location: .remote("origin"))))

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .existingBranch(
                GitBranch(name: "remote-only", location: .remote("origin"))),
            spacesURL: fixture.spacesURL)
        let dest = URL(fileURLWithPath: space.destination)

        XCTAssertEqual(space.name, "proj__remote-only")
        XCTAssertEqual(try currentBranch(in: dest), "remote-only")
        XCTAssertEqual(
            try shell.check("git", ["rev-parse", "--abbrev-ref", "@{upstream}"], cwd: dest),
            "origin/remote-only")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("REMOTE.md").path))
    }

    func testCreateSpaceFromPlainFolderCopiesFilesAndTracksIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-folder-it-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "hello\n".write(
            to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let spacesURL = root.appendingPathComponent("spaces.yaml")

        let space = try SpaceService().create(
            project: Project(name: "notes", path: source.path),
            creation: .folder(name: "Experiment"),
            spacesURL: spacesURL)

        XCTAssertEqual(space.name, "notes__experiment")
        XCTAssertEqual(space.taskType, "folder")
        XCTAssertEqual(space.taskValue, "Experiment")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("notes__experiment/README.md").path))
        XCTAssertEqual(try SpaceStore.load(url: spacesURL).spaces, [space])
    }

    func testGitServiceIdentifiesRepositoriesAndSafelyDeletesLocalBranch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gitService = GitService()
        try git(["branch", "temporary"], in: fixture.source)

        XCTAssertTrue(gitService.isRepository(repo: fixture.source))
        XCTAssertFalse(gitService.isRepository(repo: fixture.parent))

        try gitService.deleteLocalBranch(named: "temporary", repo: fixture.source)
        XCTAssertFalse(try gitService.listBranches(repo: fixture.source).contains(
            GitBranch(name: "temporary", location: .local)))

        try git(["checkout", "-b", "unmerged"], in: fixture.source)
        try commitFile("unmerged\n", named: "UNMERGED.md", message: "unmerged", in: fixture.source)
        try git(["checkout", "main"], in: fixture.source)
        XCTAssertThrowsError(
            try gitService.deleteLocalBranch(named: "unmerged", repo: fixture.source))
        XCTAssertTrue(try gitService.listBranches(repo: fixture.source).contains(
            GitBranch(name: "unmerged", location: .local)))
    }

    // MARK: - Helpers

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let remote = root.appendingPathComponent("remote.git")
        try shell.check("git", ["init", "--bare", "-b", "main", remote.path])

        let parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = parent.appendingPathComponent("proj")
        try git(["init", "-b", "main", source.path])
        try git(["config", "user.email", "test@example.com"], in: source)
        try git(["config", "user.name", "Test"], in: source)
        try commitFile("main\n", named: "README.md", message: "init", in: source)
        try git(["remote", "add", "origin", remote.path], in: source)
        try git(["push", "-u", "origin", "main"], in: source)

        return Fixture(
            root: root,
            parent: parent,
            source: source,
            remote: remote,
            spacesURL: root.appendingPathComponent("spaces.yaml"))
    }

    private func currentBranch(in repo: URL) throws -> String {
        try shell.check("git", ["branch", "--show-current"], cwd: repo)
    }

    private func git(_ args: [String], in dir: URL? = nil) throws {
        try shell.check("git", args, cwd: dir)
    }

    private func commitFile(
        _ contents: String, named name: String, message: String, in repo: URL
    ) throws {
        try contents.write(
            to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try git(["add", name], in: repo)
        try git(["commit", "-m", message], in: repo)
    }
}
