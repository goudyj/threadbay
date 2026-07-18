import Foundation
import XCTest

@testable import ThreadBay

final class GitHeadMonitorTests: XCTestCase {
    func testContinuesWatchingAfterAtomicHeadReplacement() throws {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let gitDirectory = repository.appendingPathComponent(".git", isDirectory: true)
        let head = gitDirectory.appendingPathComponent("HEAD")
        try FileManager.default.createDirectory(
            at: gitDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeBranch("main", to: head)

        let featureObserved = expectation(description: "feature branch observed")
        let releaseObserved = expectation(description: "release branch observed")
        let monitor = GitHeadMonitor(repository: repository) {
            let value = try? String(contentsOf: head, encoding: .utf8)
            if value == "ref: refs/heads/feature\n" {
                featureObserved.fulfill()
            } else if value == "ref: refs/heads/release\n" {
                releaseObserved.fulfill()
            }
        }
        XCTAssertTrue(monitor.start())
        defer { monitor.stop() }

        try writeBranch("feature", to: head)
        wait(for: [featureObserved], timeout: 2)

        try writeBranch("release", to: head)
        wait(for: [releaseObserved], timeout: 2)
    }

    private func writeBranch(_ branch: String, to head: URL) throws {
        try "ref: refs/heads/\(branch)\n".write(
            to: head, atomically: true, encoding: .utf8)
    }
}
