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

    func testAcknowledgeCurrentSessionClearsOnlyVisibleTabAttention() {
        let first = makeSession(space: space)
        first.attention = .turnEnded
        let selected = makeSession(space: space)
        selected.attention = .needsInput
        let otherSpace = makeSession(space: anotherSpace)
        otherSpace.attention = .sessionEnded
        let manager = SessionManager(sessions: [first, selected, otherSpace])
        manager.selectedID = selected.id

        manager.acknowledgeCurrentSession(in: space)

        XCTAssertEqual(first.attention, .turnEnded)
        XCTAssertEqual(selected.attention, .none)
        XCTAssertEqual(otherSpace.attention, .sessionEnded)
    }

    func testTerminalFontUpdatesExistingSessions() {
        let session = makeSession(space: space)
        let manager = SessionManager(sessions: [session])

        manager.setTerminalFont(TerminalFontSettings(family: "Monaco", size: 15))

        XCTAssertEqual(session.terminalView.font.familyName, "Monaco")
        XCTAssertEqual(session.terminalView.font.pointSize, 15)
    }

    func testSelectedSessionIsRememberedForEachSpace() {
        let first = makeSession(space: space)
        let selectedInFirstSpace = makeSession(space: space)
        let otherFirst = makeSession(space: anotherSpace)
        let selectedInOtherSpace = makeSession(space: anotherSpace)
        let manager = SessionManager(
            sessions: [first, selectedInFirstSpace, otherFirst, selectedInOtherSpace])

        manager.select(selectedInFirstSpace.id)
        manager.select(selectedInOtherSpace.id)

        XCTAssertEqual(manager.selectedSession(for: space)?.id, selectedInFirstSpace.id)
        XCTAssertEqual(manager.selectedSession(for: anotherSpace)?.id, selectedInOtherSpace.id)
    }

    func testClosingSelectedSessionUsesAnotherTabFromTheSameSpace() {
        let remaining = makeSession(space: space)
        let selected = makeSession(space: space)
        let otherSpace = makeSession(space: anotherSpace)
        let manager = SessionManager(sessions: [remaining, selected, otherSpace])
        manager.select(selected.id)

        manager.close(selected)

        XCTAssertEqual(manager.selectedSession(for: space)?.id, remaining.id)
        XCTAssertNotEqual(manager.selectedSession(for: space)?.id, otherSpace.id)
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
