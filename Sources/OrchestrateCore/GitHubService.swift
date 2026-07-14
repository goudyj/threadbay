import Foundation

public struct PullRequestSummary: Decodable, Identifiable, Hashable, Sendable {
    public let number: UInt
    public let title: String
    public let headRefName: String

    public var id: UInt { number }
}

/// Read-only GitHub queries used by the pull-request selector.
public struct GitHubService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    public func listOpenPullRequests(repo: URL) throws -> [PullRequestSummary] {
        let output = try shell.check(
            "gh",
            [
                "pr", "list",
                "--state", "open",
                "--limit", "100",
                "--json", "number,title,headRefName",
            ],
            cwd: repo)
        return try Self.decodePullRequests(output)
    }

    public func pullRequest(number: UInt, repo: URL) throws -> PullRequestSummary {
        let output = try shell.check(
            "gh",
            ["pr", "view", String(number), "--json", "number,title,headRefName"],
            cwd: repo)
        return try JSONDecoder().decode(PullRequestSummary.self, from: Data(output.utf8))
    }

    static func decodePullRequests(_ output: String) throws -> [PullRequestSummary] {
        try JSONDecoder().decode([PullRequestSummary].self, from: Data(output.utf8))
    }
}
