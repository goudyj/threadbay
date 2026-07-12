import Foundation

public enum SpaceServiceError: Error, LocalizedError {
    case emptyBranchName
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .emptyBranchName:
            return "Le nom de la branche est vide."
        case .destinationExists(let path):
            return "La destination existe déjà : \(path)"
        }
    }
}

/// Creates and deletes spaces. Ported from the CLI's `space create` (feature
/// path) in `src/space.rs` + `src/tasks.rs`, minus the mirror cache (a plain
/// local clone already hardlinks objects).
public struct SpaceService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    /// Clones `project` into a sibling directory, points its remotes at the real
    /// upstreams, copies configured files, and creates `branchName` off
    /// `baseBranch`. Persists a tracking entry and returns it.
    @discardableResult
    public func create(
        project: Project,
        branchName: String,
        baseBranch: String,
        spacesURL: URL = Paths.spacesFile
    ) throws -> TrackedSpace {
        let branch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { throw SpaceServiceError.emptyBranchName }

        let source = URL(fileURLWithPath: project.path)
        let parent = source.deletingLastPathComponent()
        let baseName = Naming.featureSpaceName(project: project.name, branch: branch)
        let finalName = Naming.ensureUniqueName(parent: parent, base: baseName)
        let dest = parent.appendingPathComponent(finalName)

        try shell.check("git", ["clone", source.path, dest.path], cwd: parent)

        do {
            try syncRemotes(source: source, dest: dest)
            try copyFiles(project.filesToInclude, into: dest)
            try shell.check("git", ["fetch", "--all", "--prune"], cwd: dest)
            try shell.check("git", ["checkout", base], cwd: dest)
            try shell.check("git", ["checkout", "-b", branch], cwd: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }

        let space = TrackedSpace(
            projectName: project.name,
            destination: dest.path,
            name: finalName,
            createdAt: Self.timestamp(),
            taskType: "feature",
            taskValue: branch)

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
