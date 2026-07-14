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
}
