import Foundation

/// Read-only git queries used to populate the create form.
public struct GitService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
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
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
