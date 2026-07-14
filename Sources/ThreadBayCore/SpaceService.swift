import Foundation

public enum SpaceServiceError: Error, LocalizedError {
    case emptyBranchName
    case emptyBaseBranch
    case emptySpaceName
    case invalidPullRequest
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .emptyBranchName:
            return "Le nom de la branche est vide."
        case .emptyBaseBranch:
            return "La branche de base est vide."
        case .emptySpaceName:
            return "Le nom de l’espace est vide."
        case .invalidPullRequest:
            return "Le numéro de pull request doit être supérieur à zéro."
        case .destinationExists(let path):
            return "La destination existe déjà : \(path)"
        }
    }
}

/// Creates and deletes spaces. Ported from the CLI's `space create` in
/// `src/space.rs` + `src/tasks.rs`, minus the mirror cache (a plain local clone
/// already hardlinks objects).
public struct SpaceService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    /// Creates a sibling directory, applies the selected creation flow,
    /// persists a tracking entry, and returns it.
    @discardableResult
    public func create(
        project: Project,
        creation: SpaceCreation,
        spacesURL: URL = Paths.spacesFile
    ) throws -> TrackedSpace {
        let creation = try normalized(creation)
        let metadata = creationMetadata(project: project, creation: creation)

        let source = URL(fileURLWithPath: project.path)
        let localUpstream = try remoteUpstream(for: creation, in: source)
        let parent = source.deletingLastPathComponent()
        let finalName = Naming.ensureUniqueName(parent: parent, base: metadata.baseName)
        let dest = parent.appendingPathComponent(finalName)

        do {
            switch creation {
            case .folder:
                try FileManager.default.copyItem(at: source, to: dest)
                try copyFiles(project.filesToInclude, into: dest)
            default:
                try shell.check("git", ["clone", source.path, dest.path], cwd: parent)
                try checkoutLocalBranchBeforeRemoteSync(creation, in: dest)
                try syncRemotes(source: source, dest: dest)
                try copyFiles(project.filesToInclude, into: dest)
                try apply(creation, localUpstream: localUpstream, in: dest)
            }
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }

        let space = TrackedSpace(
            projectName: project.name,
            destination: dest.path,
            name: finalName,
            createdAt: Self.timestamp(),
            taskType: metadata.taskType,
            taskValue: metadata.taskValue)

        var store = try SpaceStore.load(url: spacesURL)
        try store.add(space)
        return space
    }

    /// Removes the space directory (if present) and its tracking entry.
    public func delete(_ space: TrackedSpace, spacesURL: URL = Paths.spacesFile) throws {
        let dest = URL(fileURLWithPath: space.destination)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        var store = try SpaceStore.load(url: spacesURL)
        try store.remove(named: space.name)
    }

    // MARK: - Helpers (ported from `sync_remotes` in src/space.rs)

    private func normalized(_ creation: SpaceCreation) throws -> SpaceCreation {
        switch creation {
        case .feature(let branchName, let base):
            let branchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !branchName.isEmpty else { throw SpaceServiceError.emptyBranchName }
            let base = normalizedBranch(base)
            guard !base.name.isEmpty else { throw SpaceServiceError.emptyBaseBranch }
            return .feature(branchName: branchName, base: base)
        case .existingBranch(let branch):
            let branch = normalizedBranch(branch)
            guard !branch.name.isEmpty else { throw SpaceServiceError.emptyBranchName }
            return .existingBranch(branch)
        case .pullRequest(let number):
            guard number > 0 else { throw SpaceServiceError.invalidPullRequest }
            return .pullRequest(number)
        case .folder(let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw SpaceServiceError.emptySpaceName }
            return .folder(name: name)
        }
    }

    private func normalizedBranch(_ branch: GitBranch) -> GitBranch {
        let name = branch.name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch branch.location {
        case .local:
            return GitBranch(name: name, location: .local)
        case .remote(let remote):
            return GitBranch(
                name: name,
                location: .remote(remote.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    private func creationMetadata(
        project: Project, creation: SpaceCreation
    ) -> (baseName: String, taskType: String, taskValue: String) {
        switch creation {
        case .feature(let branchName, _):
            return (
                Naming.branchSpaceName(project: project.name, branch: branchName),
                "feature",
                branchName)
        case .existingBranch(let branch):
            return (
                Naming.branchSpaceName(project: project.name, branch: branch.name),
                "review",
                "branch-\(branch.name)")
        case .pullRequest(let number):
            return (
                Naming.pullRequestSpaceName(project: project.name, number: number),
                "review",
                "pr-\(number)")
        case .folder(let name):
            let slug = Naming.slugify(name)
            return (
                "\(project.name)__\(slug.isEmpty ? "space" : slug)",
                "folder",
                name)
        }
    }

    /// A local-only branch is available through the clone's temporary `origin`.
    /// Check it out before that remote is repointed and pruned.
    private func checkoutLocalBranchBeforeRemoteSync(
        _ creation: SpaceCreation, in repo: URL
    ) throws {
        if let localBranch = selectedLocalBranch(in: creation) {
            try shell.check("git", ["checkout", localBranch.name], cwd: repo)
        }
    }

    private func selectedLocalBranch(in creation: SpaceCreation) -> GitBranch? {
        switch creation {
        case .feature(_, let base), .existingBranch(let base):
            if case .local = base.location {
                return base
            }
            return nil
        case .pullRequest, .folder:
            return nil
        }
    }

    /// The clone temporarily calls the source repo `origin`, so capture the
    /// selected local branch's actual remote upstream before cloning it.
    private func remoteUpstream(for creation: SpaceCreation, in repo: URL) throws -> String? {
        guard let branch = selectedLocalBranch(in: creation) else { return nil }
        let output = try shell.check(
            "git",
            [
                "for-each-ref",
                "--format=%(upstream:remotename)%09%(upstream:short)",
                "refs/heads/\(branch.name)",
            ],
            cwd: repo)
        let fields = output.split(whereSeparator: \Character.isWhitespace)
        guard fields.count == 2, fields[0] != "." else { return nil }
        return String(fields[1])
    }

    private func apply(
        _ creation: SpaceCreation, localUpstream: String?, in repo: URL
    ) throws {
        switch creation {
        case .feature(let branchName, let base):
            try shell.check("git", ["fetch", "--all", "--prune"], cwd: repo)
            try fastForward(to: localUpstream, in: repo)
            if case .remote(let remote) = base.location {
                try shell.check("git", ["checkout", "\(remote)/\(base.name)"], cwd: repo)
            }
            try shell.check("git", ["checkout", "-b", branchName], cwd: repo)
        case .existingBranch(let branch):
            try shell.check("git", ["fetch", "--all", "--prune"], cwd: repo)
            try fastForward(to: localUpstream, in: repo)
            if case .remote(let remote) = branch.location {
                try shell.check(
                    "git",
                    ["checkout", "-B", branch.name, "--track", "\(remote)/\(branch.name)"],
                    cwd: repo)
            }
        case .pullRequest(let number):
            try shell.check("gh", ["pr", "checkout", String(number)], cwd: repo)
        case .folder:
            break
        }
    }

    private func fastForward(to upstream: String?, in repo: URL) throws {
        guard let upstream else { return }
        try shell.check("git", ["merge", "--ff-only", "--", upstream], cwd: repo)
    }

    private func syncRemotes(source: URL, dest: URL) throws {
        let sourceRemotes = try listRemotes(source)
        guard !sourceRemotes.isEmpty else { return }
        let destRemotes = Set(try listRemotes(dest))

        for name in sourceRemotes {
            let url = try shell.check("git", ["remote", "get-url", name], cwd: source)
            if destRemotes.contains(name) {
                try shell.check("git", ["remote", "set-url", name, url], cwd: dest)
            } else {
                try shell.check("git", ["remote", "add", name, url], cwd: dest)
            }

            if let pushURL = try? shell.check("git", ["remote", "get-url", "--push", name], cwd: source),
                !pushURL.isEmpty, pushURL != url
            {
                try shell.check("git", ["remote", "set-url", "--push", name, pushURL], cwd: dest)
            }
        }
    }

    private func listRemotes(_ repo: URL) throws -> [String] {
        try shell.check("git", ["remote"], cwd: repo)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func copyFiles(_ files: [String], into dest: URL) throws {
        for file in files {
            let src = URL(fileURLWithPath: file)
            let target = dest.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: src, to: target)
        }
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
