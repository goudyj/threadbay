import XCTest

@testable import ThreadBayCore

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("threadbay-agent-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let sampleSpace = TrackedSpace(
    projectName: "demo",
    destination: "/tmp/spaces/demo-feature",
    name: "demo-feature",
    createdAt: "2026-07-12T10:00:00Z",
    taskType: "feature",
    taskValue: "feat/terminal")

final class AgentLibraryTests: XCTestCase {
    func testFirstLoadCreatesDefaults() throws {
        let url = try makeTempDir().appendingPathComponent("agents.yaml")
        let library = try AgentLibrary.load(url: url)
        XCTAssertEqual(library.agents.map(\.name), ["Claude", "Codex", "Shell"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Reload reads the persisted file, not the defaults.
        let reloaded = try AgentLibrary.load(url: url)
        XCTAssertEqual(reloaded.agents, library.agents)
    }

    func testRoundTripsCustomAgent() throws {
        let url = try makeTempDir().appendingPathComponent("agents.yaml")
        var library = try AgentLibrary.load(url: url)
        library.agents.append(AgentDefinition(name: "Dev server", command: "npm run dev"))
        try library.save(url: url)
        let reloaded = try AgentLibrary.load(url: url)
        XCTAssertEqual(reloaded.agents.last, AgentDefinition(name: "Dev server", command: "npm run dev"))
        XCTAssertEqual(reloaded.agents.last?.kind, .custom)
    }

    func testRoundTripsCustomCommitGenerator() throws {
        let url = try makeTempDir().appendingPathComponent("agents.yaml")
        let library = AgentLibrary(
            agents: AgentLibrary.defaults.agents,
            commitGenerators: [
                CommitGeneratorDefinition(name: "Local", command: "generate-commit"),
            ])
        try library.save(url: url)

        let reloaded = try AgentLibrary.load(url: url)
        XCTAssertEqual(reloaded.commitGenerators, library.commitGenerators)
    }
}

final class CommandTemplateTests: XCTestCase {
    func testRendersPlaceholders() {
        let rendered = CommandTemplate.render(
            "run --dir {space_path} --branch {branch} ({task_value}) {name}@{project}",
            space: sampleSpace)
        XCTAssertEqual(
            rendered,
            "run --dir /tmp/spaces/demo-feature --branch feat/terminal (feat/terminal) demo-feature@demo"
        )
    }

    func testShellQuoting() {
        XCTAssertEqual("plain".shellQuoted, "'plain'")
        XCTAssertEqual("it's".shellQuoted, "'it'\\''s'")
    }

    func testCurrentBranchOverridesCreationTaskForBranchPlaceholder() {
        let rendered = CommandTemplate.render(
            "{branch} ({task_value})",
            space: sampleSpace,
            currentBranch: "release/2.0")
        XCTAssertEqual(rendered, "release/2.0 (feat/terminal)")
    }
}

final class HookInjectionTests: XCTestCase {
    func testCreatesClaudeSettingsFromScratch() throws {
        let data = try HookInjection.claudeSettings(
            merging: nil, notifierPath: "/tmp/threadbay-notify")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["UserPromptSubmit"])
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["Notification"])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let entries = try XCTUnwrap(stop.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(
            entries.first?["command"] as? String,
            "'/tmp/threadbay-notify' claude-stop")
    }

    func testMergePreservesForeignKeys() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "permissions": ["allow": ["Bash"]],
            "hooks": ["PreToolUse": [["hooks": [["type": "command", "command": "echo hi"]]]]],
        ])
        let data = try HookInjection.claudeSettings(
            merging: existing, notifierPath: "/tmp/threadbay-notify")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(root["permissions"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNotNil(hooks["Stop"])
    }

    func testInjectsIntoSpaceDirectory() throws {
        let dir = try makeTempDir()
        try HookInjection.injectClaudeHooks(
            spaceDir: dir, notifierPath: "/tmp/threadbay-notify")
        let file = dir.appendingPathComponent(".claude/settings.local.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // Idempotent: a second injection still parses and keeps both hooks.
        try HookInjection.injectClaudeHooks(
            spaceDir: dir, notifierPath: "/tmp/threadbay-notify")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(hooks.count, 3)
    }

    func testCodexOverride() {
        XCTAssertEqual(
            HookInjection.codexNotifyOverride(notifierPath: "/tmp/threadbay-notify"),
            "notify=[\"/tmp/threadbay-notify\",\"codex-notify\"]")
    }
}

final class AgentEventTests: XCTestCase {
    private let id = UUID()

    private func event(kind: String, payload: String) -> AgentEvent? {
        let json = #"{"session_id":"\#(id.uuidString)","kind":"\#(kind)","payload":\#(payload)}"#
        return AgentEvent.parse(Data(json.utf8))
    }

    func testParsesClaudePrompt() {
        let parsed = event(kind: "claude-prompt", payload: #"{"prompt":"fais X"}"#)
        XCTAssertEqual(parsed, AgentEvent(sessionID: id, kind: .turnStarted))
    }

    func testParsesClaudeStop() {
        let parsed = event(kind: "claude-stop", payload: #"{"session_id":"abc"}"#)
        XCTAssertEqual(parsed, AgentEvent(sessionID: id, kind: .turnEnded))
    }

    func testParsesClaudeNotification() {
        let parsed = event(
            kind: "claude-notification",
            payload: #"{"message":"Claude needs your permission to use Bash"}"#)
        XCTAssertEqual(parsed?.kind, .needsInput)
        XCTAssertEqual(parsed?.message, "Claude needs your permission to use Bash")
    }

    func testParsesCodexNotify() {
        let parsed = event(
            kind: "codex-notify",
            payload: #"{"type":"agent-turn-complete","last-assistant-message":"Done"}"#)
        XCTAssertEqual(parsed?.kind, .turnEnded)
        XCTAssertEqual(parsed?.message, "Done")
    }

    func testParsesNullPayloadAndUnknownKind() {
        let parsed = event(kind: "mystery", payload: "null")
        XCTAssertEqual(parsed?.kind, .unknown("mystery"))
        XCTAssertNil(AgentEvent.parse(Data("not json".utf8)))
    }
}

final class EventSocketServerTests: XCTestCase {
    func testReceivesEventFromNotifierClient() throws {
        let path = "/tmp/threadbay-test-\(UUID().uuidString.prefix(8)).sock"
        let sessionID = UUID()
        let received = expectation(description: "event received")
        let box = ReceivedBox()
        let server = EventSocketServer(path: path) { data in
            box.append(data)
            received.fulfill()
        }
        try server.start()
        defer { server.stop() }

        try AgentEventNotifier.send(
            sessionID: sessionID,
            kind: HookInjection.claudeNotificationKind,
            payload: Data(#"{"message":"Permission needed"}"#.utf8),
            socketPath: path)

        wait(for: [received], timeout: 5)
        let data = try XCTUnwrap(box.all().first)
        XCTAssertEqual(
            AgentEvent.parse(data),
            AgentEvent(
                sessionID: sessionID,
                kind: .needsInput,
                message: "Permission needed"))
    }

    private final class ReceivedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Data] = []
        func append(_ data: Data) {
            lock.lock()
            items.append(data)
            lock.unlock()
        }
        func all() -> [Data] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }
}
