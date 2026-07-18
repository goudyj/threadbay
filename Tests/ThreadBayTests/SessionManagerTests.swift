import XCTest

@testable import ThreadBay
import ThreadBayCore

@MainActor
final class SessionManagerTests: XCTestCase {
    func testAttentionCountIncludesOnlyUnacknowledgedSessionsInSpace() {
        let first = makeSession(space: space)
        first.attention = .turnEnded
        let second = makeSession(space: space)
        second.attention = .needsInput
        let acknowledged = makeSession(space: space)
        let otherSpace = makeSession(space: anotherSpace)
        otherSpace.attention = .sessionEnded
        let manager = SessionManager(sessions: [first, second, acknowledged, otherSpace])

        XCTAssertEqual(manager.attentionCount(for: space), 2)

        manager.select(first.id)

        XCTAssertEqual(manager.attentionCount(for: space), 1)
    }

    private func makeSession(space: TrackedSpace) -> AgentSession {
        AgentSession(
            space: space,
            agent: AgentDefinition(name: "Test", command: ""),
            notifierPath: nil)
    }

    private var space: TrackedSpace {
        TrackedSpace(
            projectName: "demo",
            destination: "/tmp/demo-one",
            name: "demo-one",
            createdAt: "2026-07-18T00:00:00Z",
            taskType: "feature",
            taskValue: "one")
    }

    private var anotherSpace: TrackedSpace {
        TrackedSpace(
            projectName: "demo",
            destination: "/tmp/demo-two",
            name: "demo-two",
            createdAt: "2026-07-18T00:00:00Z",
            taskType: "feature",
            taskValue: "two")
    }
}
