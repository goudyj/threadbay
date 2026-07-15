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
            displayName: "Test space",
            spacesURL: fixture.spacesURL)

        let dest = URL(fileURLWithPath: space.destination)
        XCTAssertTrue(space.name.hasPrefix("proj__"), space.name)
        XCTAssertFalse(space.name.contains("feat-test"), space.name)
        XCTAssertEqual(space.destination, dest.path)
        XCTAssertEqual(space.taskType, "feature")
        XCTAssertEqual(space.taskValue, "feat/test")
        XCTAssertEqual(space.displayName, "Test space")
        XCTAssertEqual(space.displayTitle, "Test space")
        XCTAssertEqual(try currentBranch(in: dest), "feat/test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("BASE.md").path))
        XCTAssertEqual(
            try shell.check("git", ["remote", "get-url", "origin"], cwd: dest),
            fixture.remote.path)
        XCTAssertEqual(
            GitService().baseBranch(repo: dest),
            GitBranch(name: "base", location: .remote("origin")))

        var store = try SpaceStore.load(url: fixture.spacesURL)
        XCTAssertEqual(store.spaces.map(\.name), [space.name])

        try SpaceService().delete(space, spacesURL: fixture.spacesURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        store = try SpaceStore.load(url: fixture.spacesURL)
        XCTAssertTrue(store.spaces.isEmpty)
    }

    func testCreateTerminalSpaceOnlyTracksAndNeverDeletesItsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-terminal-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let spacesURL = root.appendingPathComponent("spaces.yaml")

        let space = try SpaceService().createTerminal(home: home, spacesURL: spacesURL)

        XCTAssertEqual(space.taskType, "terminal")
        XCTAssertEqual(space.projectName, "Terminal")
        XCTAssertEqual(space.destination, home.path)
        XCTAssertTrue(space.isTerminal)
        XCTAssertFalse(space.supportsGitActions)
        XCTAssertEqual(try SpaceStore.load(url: spacesURL).spaces.map(\.name), [space.name])

        // A second space gets a distinct name even though no folder exists.
        let second = try SpaceService().createTerminal(home: home, spacesURL: spacesURL)
        XCTAssertNotEqual(second.name, space.name)

        try SpaceService().delete(space, spacesURL: spacesURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.path))
        XCTAssertEqual(try SpaceStore.load(url: spacesURL).spaces.map(\.name), [second.name])
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

        XCTAssertTrue(space.name.hasPrefix("proj__"), space.name)
        XCTAssertEqual(space.taskType, "review")
        XCTAssertEqual(space.taskValue, "branch-local-only")
        XCTAssertEqual(try currentBranch(in: dest), "local-only")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("LOCAL.md").path))
    }

    func testCreateFromLocalBranchFastForwardsItsRemoteUpstream() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try git(["remote", "rename", "origin", "upstream"], in: fixture.source)
        try commitFile("remote\n", named: "REMOTE.md", message: "remote", in: fixture.source)
        try git(["push", "upstream", "main"], in: fixture.source)
        try git(["reset", "--hard", "HEAD~1"], in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .existingBranch(GitBranch(name: "main", location: .local)),
            spacesURL: fixture.spacesURL)
        let dest = URL(fileURLWithPath: space.destination)

        XCTAssertEqual(try currentBranch(in: dest), "main")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("REMOTE.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.source.appendingPathComponent("REMOTE.md").path))
    }

    func testCreateFeatureFromLocalBaseFastForwardsBeforeCreatingBranch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try commitFile("remote\n", named: "REMOTE.md", message: "remote", in: fixture.source)
        try git(["push", "origin", "main"], in: fixture.source)
        try git(["reset", "--hard", "HEAD~1"], in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .feature(
                branchName: "feat/fresh-base",
                base: GitBranch(name: "main", location: .local)),
            spacesURL: fixture.spacesURL)
        let dest = URL(fileURLWithPath: space.destination)

        XCTAssertEqual(try currentBranch(in: dest), "feat/fresh-base")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("REMOTE.md").path))
    }

    func testCreateFromDivergedLocalBranchFailsWithoutMerging() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try commitFile("remote\n", named: "REMOTE.md", message: "remote", in: fixture.source)
        try git(["push", "origin", "main"], in: fixture.source)
        try git(["reset", "--hard", "HEAD~1"], in: fixture.source)
        try commitFile("local\n", named: "LOCAL.md", message: "local", in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let childrenBefore = try FileManager.default.contentsOfDirectory(
            atPath: fixture.parent.path).sorted()
        XCTAssertThrowsError(try SpaceService().create(
            project: project,
            creation: .existingBranch(GitBranch(name: "main", location: .local)),
            spacesURL: fixture.spacesURL))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path).sorted(),
            childrenBefore)
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

        XCTAssertTrue(space.name.hasPrefix("proj__"), space.name)
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

        XCTAssertTrue(space.name.hasPrefix("notes__"), space.name)
        XCTAssertEqual(space.taskType, "folder")
        XCTAssertEqual(space.taskValue, "Experiment")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: space.destination)
                .appendingPathComponent("README.md").path))
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

    func testGitActionsCommitPushMergeAndSwitchWithoutMovingFeatureBranch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try git(["checkout", "-b", "other"], in: fixture.source)
        try commitFile("other\n", named: "OTHER.md", message: "other", in: fixture.source)
        try git(["push", "-u", "origin", "other"], in: fixture.source)
        try git(["checkout", "main"], in: fixture.source)
        try git(["branch", "-D", "other"], in: fixture.source)

        let project = Project(name: "proj", path: fixture.source.path)
        let space = try SpaceService().create(
            project: project,
            creation: .feature(
                branchName: "feat/actions",
                base: GitBranch(name: "main", location: .remote("origin"))),
            spacesURL: fixture.spacesURL)
        let repo = URL(fileURLWithPath: space.destination)
        let gitService = GitService()

        try "change\n".write(
            to: repo.appendingPathComponent("CHANGE.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try gitService.changedFiles(repo: repo), ["CHANGE.md"])

        XCTAssertThrowsError(try gitService.commitAll(
            message: "feat: stale preview", expectedFiles: [], repo: repo)) { error in
            guard case GitActionError.changesChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        try gitService.commitAll(message: "feat: add change", repo: repo)
        XCTAssertTrue(try gitService.changedFiles(repo: repo).isEmpty)
        XCTAssertEqual(try currentBranch(in: repo), "feat/actions")
        try gitService.pushCurrentBranch(repo: repo)

        let featureHead = try shell.check("git", ["rev-parse", "HEAD"], cwd: repo)
        XCTAssertEqual(
            try shell.check(
                "git", ["--git-dir", fixture.remote.path, "rev-parse", "feat/actions"]),
            featureHead)

        try gitService.mergeCurrentBranch(
            into: GitBranch(name: "main", location: .remote("origin")),
            push: true,
            repo: repo)

        XCTAssertEqual(try currentBranch(in: repo), "feat/actions")
        XCTAssertEqual(
            try shell.check("git", ["--git-dir", fixture.remote.path, "rev-parse", "main"]),
            featureHead)

        _ = try gitService.switchBranch(
            GitBranch(name: "main", location: .local), repo: repo)
        XCTAssertEqual(try currentBranch(in: repo), "main")
        XCTAssertEqual(try gitService.repositoryState(repo: repo).currentBranch, "main")

        _ = try gitService.switchBranch(
            GitBranch(name: "other", location: .remote("origin")), repo: repo)
        XCTAssertEqual(try currentBranch(in: repo), "other")
        XCTAssertEqual(
            try shell.check("git", ["rev-parse", "--abbrev-ref", "@{upstream}"], cwd: repo),
            "origin/other")
    }

    func testCustomCommitGeneratorReadsContextFromStandardInput() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try "change\n".write(
            to: fixture.source.appendingPathComponent("CHANGE.md"),
            atomically: true,
            encoding: .utf8)

        let message = try CommitMessageService().generate(
            provider: .custom(command: "cat >/dev/null; printf 'feat: generated'"),
            repo: fixture.source)

        XCTAssertEqual(message, "feat: generated")
    }

    func testSwitchBranchCanChangeHeadBeforePostCheckoutHookFailure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try git(["branch", "other"], in: fixture.source)

        let hook = fixture.source.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\nexit 1\n".write(
            to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let result = try GitService().switchBranch(
            GitBranch(name: "other", location: .local), repo: fixture.source)
        guard case .switchedWithWarning(let detail) = result else {
            return XCTFail("Expected a successful switch with a hook warning")
        }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertEqual(try currentBranch(in: fixture.source), "other")
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
