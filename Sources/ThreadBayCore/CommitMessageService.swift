import Foundation

public enum CommitMessageProvider: Sendable {
    case claude
    case codex
    case custom(command: String)
}

public struct CommitMessageService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    public func generate(provider: CommitMessageProvider, repo: URL) throws -> String {
        let prompt = try prompt(repo: repo)
        let output: String
        switch provider {
        case .claude:
            output = try shell.check(
                "claude", ["-p", "--tools", ""], cwd: repo, input: prompt)
        case .codex:
            output = try shell.check(
                "codex", ["exec", "--sandbox", "read-only", "--ephemeral", "-"],
                cwd: repo,
                input: prompt)
        case .custom(let command):
            output = try shell.check("zsh", ["-lc", command], cwd: repo, input: prompt)
        }
        return Self.normalizedMessage(output)
    }

    private func prompt(repo: URL) throws -> String {
        let status = try shell.check(
            "git", ["status", "--short", "--untracked-files=normal"], cwd: repo)
        let diff = try shell.check("git", ["diff", "--no-ext-diff", "HEAD", "--"], cwd: repo)
        let limitedDiff = String(diff.prefix(120_000))
        return """
            Write a concise Conventional Commit message for the changes below.
            Return only the commit message: a subject line, then an optional body.
            Do not use Markdown fences and do not discuss the result.

            Git status:
            \(status)

            Git diff:
            \(limitedDiff)
            """
    }

    private static func normalizedMessage(_ output: String) -> String {
        var message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix("```") {
            message = message
                .replacingOccurrences(of: "```text", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return message
    }
}
