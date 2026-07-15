import Foundation

public enum GitActionError: Error, Sendable {
    case emptyCommitMessage
    case noChanges
    case uncommittedChanges
    case noCurrentBranch
    case noPushRemote
    case currentBranchIsMergeTarget
    case changesChanged
}

public enum GitSwitchResult: Equatable, Sendable {
    case switched
    case switchedWithWarning(String)
}

/// Git operations used by the create and space-management screens.
public struct GitService: Sendable {
    private static let baseBranchKey = "threadbay.baseBranch"
    private static let baseRemoteKey = "threadbay.baseRemote"

    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    /// Whether `repo` itself is a Git worktree root. A nested folder does not
    /// count because ThreadBay clones configured projects by their root path.
    public func isRepository(repo: URL) -> Bool {
        guard let root = try? shell.check("git", ["rev-parse", "--show-toplevel"], cwd: repo)
        else { return false }
        return URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
            == repo.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Local and remote branches offered by the create form. Local and remote
    /// references stay distinct even when they share the same branch name.
    public func listBranches(repo: URL) throws -> [GitBranch] {
        let output = try shell.check(
            "git",
            ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"],
            cwd: repo)

        var branches: [GitBranch] = []
        for raw in output.split(separator: "\n") {
            let ref = raw.trimmingCharacters(in: .whitespaces)
            if let name = ref.removingPrefix("refs/heads/"), !name.isEmpty {
                branches.append(GitBranch(name: name, location: .local))
                continue
            }

            guard let remoteRef = ref.removingPrefix("refs/remotes/"),
                let slash = remoteRef.firstIndex(of: "/")
            else { continue }

            let remote = String(remoteRef[..<slash])
            let name = String(remoteRef[remoteRef.index(after: slash)...])
            if name != "HEAD" && !name.isEmpty {
                branches.append(GitBranch(name: name, location: .remote(remote)))
            }
        }
        return branches.sorted {
            $0.referenceName.localizedCaseInsensitiveCompare($1.referenceName) == .orderedAscending
        }
    }

    /// Refreshes remote references before returning the branch list.
    public func refreshBranches(repo: URL) throws -> [GitBranch] {
        try shell.check("git", ["fetch", "--all", "--prune"], cwd: repo)
        return try listBranches(repo: repo)
    }

    /// The source repo's current branch — the default base, matching the CLI's
    /// `resolve_feature_base_branch` (`src/git.rs`).
    public func currentBranch(repo: URL) -> String? {
        let result = try? shell.run("git", ["branch", "--show-current"], cwd: repo)
        guard let branch = result?.stdout, !branch.isEmpty else { return nil }
        return branch
    }

    /// Stores the integration target in this clone only. Git remains the source
    /// of truth for the mutable current branch.
    public func setBaseBranch(_ branch: GitBranch, repo: URL) throws {
        try shell.check("git", ["config", "--local", Self.baseBranchKey, branch.name], cwd: repo)
        if case .remote(let remote) = branch.location {
            try shell.check("git", ["config", "--local", Self.baseRemoteKey, remote], cwd: repo)
        } else {
            _ = try? shell.run(
                "git", ["config", "--local", "--unset", Self.baseRemoteKey], cwd: repo)
        }
    }

    public func baseBranch(repo: URL) -> GitBranch? {
        guard let name = try? shell.check(
            "git", ["config", "--local", "--get", Self.baseBranchKey], cwd: repo),
            !name.isEmpty
        else { return nil }

        if let remote = try? shell.check(
            "git", ["config", "--local", "--get", Self.baseRemoteKey], cwd: repo),
            !remote.isEmpty
        {
            return GitBranch(name: name, location: .remote(remote))
        }
        return GitBranch(name: name, location: .local)
    }

    public func repositoryState(repo: URL) throws -> GitRepositoryState {
        let changes = try shell.check(
            "git", ["status", "--porcelain", "--untracked-files=normal"], cwd: repo)
        return GitRepositoryState(
            currentBranch: currentBranch(repo: repo),
            baseBranch: baseBranch(repo: repo),
            hasChanges: !changes.isEmpty)
    }

    public func switchBranch(_ branch: GitBranch, repo: URL) throws -> GitSwitchResult {
        do {
            switch branch.location {
            case .local:
                try shell.check("git", ["switch", "--", branch.name], cwd: repo)
            case .remote(let remote):
                let localRef = "refs/heads/\(branch.name)"
                let localExists = try shell.run(
                    "git", ["show-ref", "--verify", "--quiet", localRef], cwd: repo).isSuccess
                if localExists {
                    try shell.check("git", ["switch", "--", branch.name], cwd: repo)
                } else {
                    try shell.check(
                        "git",
                        ["switch", "--track", "-c", branch.name, "\(remote)/\(branch.name)"],
                        cwd: repo)
                }
            }
            return .switched
        } catch {
            // post-checkout hooks run after HEAD changes. Their non-zero exit is
            // reported by Git even though the requested switch already happened.
            guard currentBranch(repo: repo) == branch.name else { throw error }
            return .switchedWithWarning(error.localizedDescription)
        }
    }

    public func changedFiles(repo: URL) throws -> [String] {
        try shell.check(
            "git", ["status", "--short", "--untracked-files=normal"], cwd: repo)
            .split(separator: "\n")
            .map { line in
                let value = String(line)
                return value.count > 3 ? String(value.dropFirst(3)) : value
            }
    }

    public func commitAll(
        message: String,
        expectedFiles: [String]? = nil,
        repo: URL
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitActionError.emptyCommitMessage }
        let files = try changedFiles(repo: repo)
        guard !files.isEmpty else { throw GitActionError.noChanges }
        if let expectedFiles, files.sorted() != expectedFiles.sorted() {
            throw GitActionError.changesChanged
        }
        try shell.check("git", ["add", "-A", "--"], cwd: repo)
        try shell.check("git", ["commit", "-m", message], cwd: repo)
    }

    public func pushCurrentBranch(forceWithLease: Bool = false, repo: URL) throws {
        guard let branch = currentBranch(repo: repo) else {
            throw GitActionError.noCurrentBranch
        }
        let force = forceWithLease ? ["--force-with-lease"] : []
        if try upstreamRemote(for: branch, repo: repo) != nil {
            try shell.check("git", ["push"] + force, cwd: repo)
        } else {
            let remote = try defaultRemote(repo: repo)
            try shell.check("git", ["push", "-u"] + force + [remote, branch], cwd: repo)
        }
    }

    /// Merges without changing the space's checked-out branch. The target is
    /// checked out in a temporary linked worktree owned by this clone.
    public func mergeCurrentBranch(
        into target: GitBranch,
        push: Bool,
        repo: URL
    ) throws {
        guard let current = currentBranch(repo: repo) else {
            throw GitActionError.noCurrentBranch
        }
        guard current != target.name else {
            throw GitActionError.currentBranchIsMergeTarget
        }
        guard try changedFiles(repo: repo).isEmpty else {
            throw GitActionError.uncommittedChanges
        }

        let remote: String?
        switch target.location {
        case .local:
            remote = try upstreamRemote(for: target.name, repo: repo)
        case .remote(let name):
            remote = name
            let localExists = try shell.run(
                "git", ["show-ref", "--verify", "--quiet", "refs/heads/\(target.name)"],
                cwd: repo).isSuccess
            if !localExists {
                try shell.check(
                    "git", ["branch", target.name, "\(name)/\(target.name)"], cwd: repo)
            }
        }

        if let remote {
            try shell.check("git", ["fetch", remote, target.name], cwd: repo)
        }

        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-merge-\(UUID().uuidString)")
        try shell.check("git", ["worktree", "add", worktree.path, target.name], cwd: repo)
        defer {
            _ = try? shell.run(
                "git", ["worktree", "remove", "--force", worktree.path], cwd: repo)
            _ = try? shell.run("git", ["worktree", "prune"], cwd: repo)
        }

        if let remote {
            try shell.check(
                "git", ["merge", "--ff-only", "\(remote)/\(target.name)"], cwd: worktree)
        }
        try shell.check("git", ["merge", "--no-edit", current], cwd: worktree)
        if push {
            let pushRemote = try remote ?? defaultRemote(repo: repo)
            try shell.check(
                "git", ["push", pushRemote, "\(target.name):\(target.name)"], cwd: worktree)
        }
        try setBaseBranch(target, repo: repo)
    }

    /// Deletes only a merged local branch. Git itself rejects the current
    /// branch, an unmerged branch, or one checked out in another worktree.
    public func deleteLocalBranch(named name: String, repo: URL) throws {
        try shell.check("git", ["branch", "-d", "--", name], cwd: repo)
    }

    private func upstreamRemote(for branch: String, repo: URL) throws -> String? {
        let value = try shell.check(
            "git",
            [
                "for-each-ref", "--format=%(upstream:remotename)",
                "refs/heads/\(branch)",
            ],
            cwd: repo)
        return value.isEmpty || value == "." ? nil : value
    }

    private func defaultRemote(repo: URL) throws -> String {
        let remotes = try shell.check("git", ["remote"], cwd: repo)
            .split(separator: "\n").map(String.init)
        if remotes.contains("origin") { return "origin" }
        guard remotes.count == 1, let remote = remotes.first else {
            throw GitActionError.noPushRemote
        }
        return remote
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
