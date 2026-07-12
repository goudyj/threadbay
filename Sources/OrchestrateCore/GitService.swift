import Foundation

/// Read-only git queries used to populate the create form.
public struct GitService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    /// Branch names offered as a base: local heads plus remote branches with the
    /// `origin/` prefix stripped, deduplicated and sorted. `HEAD` is excluded.
    public func listBranches(repo: URL) throws -> [String] {
        let output = try shell.check(
            "git",
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
            cwd: repo)

        var seen = Set<String>()
        var names: [String] = []
        for raw in output.split(separator: "\n") {
            var name = raw.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            if let slash = name.firstIndex(of: "/"), name.hasPrefix("origin/") {
                name = String(name[name.index(after: slash)...])
            }
            if name == "HEAD" || name.isEmpty { continue }
            if seen.insert(name).inserted { names.append(name) }
        }
        return names.sorted()
    }

    /// The source repo's current branch — the default base, matching the CLI's
    /// `resolve_feature_base_branch` (`src/git.rs`).
    public func currentBranch(repo: URL) -> String? {
        let result = try? shell.run("git", ["branch", "--show-current"], cwd: repo)
        guard let branch = result?.stdout, !branch.isEmpty else { return nil }
        return branch
    }
}
