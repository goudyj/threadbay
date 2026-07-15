import XCTest

@testable import ThreadBayCore

final class GitHubServiceTests: XCTestCase {
    func testDecodesPullRequestSummariesFromGitHubCLI() throws {
        let output = """
            [
              {"number":42,"title":"Add search","headRefName":"feat/search"},
              {"number":7,"title":"Fix checkout","headRefName":"fix/checkout"}
            ]
            """

        let pullRequests = try GitHubService.decodePullRequests(output)

        XCTAssertEqual(pullRequests.map(\.number), [42, 7])
        XCTAssertEqual(pullRequests.first?.title, "Add search")
        XCTAssertEqual(pullRequests.first?.headRefName, "feat/search")
    }

    func testListingPullRequestsWithoutRemoteThrowsNoRemote() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-gh-\(UUID().uuidString)")
        try Shell.shared.check("git", ["init", "-b", "main", repo.path])
        defer { try? FileManager.default.removeItem(at: repo) }

        XCTAssertThrowsError(try GitHubService().listOpenPullRequests(repo: repo)) { error in
            guard case GitHubServiceError.noRemote = error else {
                return XCTFail("Expected GitHubServiceError.noRemote, got \(error)")
            }
        }
    }
}
