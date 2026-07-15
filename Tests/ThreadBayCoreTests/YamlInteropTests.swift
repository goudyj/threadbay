import XCTest
import Yams

@testable import ThreadBayCore

final class YamlInteropTests: XCTestCase {
    /// The exact shape the CLI writes today (`threadbay settings`).
    private let settingsYAML = """
        default_project: threadbay
        projects:
        - name: threadbay
          path: /Users/jean/Documents/developpement/threadbay
          files_to_include: []
        agent_commands:
          review: pi "Use the assisted-review-2 skill to review {task_value}"
          feature: pi
        """

    private let spacesYAML = """
        spaces:
        - project_name: threadbay
          destination: /Users/jean/Documents/developpement/threadbay__feature-x
          name: threadbay__feature-x
          created_at: 2026-07-10T12:34:56Z
          task_type: feature
          task_value: feat/x
        """

    func testDecodeSettings() throws {
        let settings = try YAMLDecoder().decode(Settings.self, from: settingsYAML)
        XCTAssertEqual(settings.defaultProject, "threadbay")
        XCTAssertEqual(settings.projects.count, 1)
        XCTAssertEqual(settings.projects[0].name, "threadbay")
        XCTAssertEqual(settings.projects[0].path, "/Users/jean/Documents/developpement/threadbay")
        XCTAssertEqual(settings.projects[0].filesToInclude, [])
        XCTAssertEqual(settings.agentCommands.feature, "pi")
        XCTAssertNotNil(settings.agentCommands.review)
    }

    func testSettingsRoundTripPreservesAgentCommands() throws {
        let settings = try YAMLDecoder().decode(Settings.self, from: settingsYAML)
        let encoded = try YAMLEncoder().encode(settings)
        let again = try YAMLDecoder().decode(Settings.self, from: encoded)
        XCTAssertEqual(again.defaultProject, "threadbay")
        XCTAssertEqual(again.agentCommands.review, settings.agentCommands.review)
        XCTAssertEqual(again.agentCommands.feature, "pi")
        XCTAssertEqual(again.projects, settings.projects)
    }

    func testDecodeSpaces() throws {
        struct Registry: Codable { var spaces: [TrackedSpace] }
        let registry = try YAMLDecoder().decode(Registry.self, from: spacesYAML)
        XCTAssertEqual(registry.spaces.count, 1)
        let space = registry.spaces[0]
        XCTAssertEqual(space.projectName, "threadbay")
        XCTAssertEqual(space.name, "threadbay__feature-x")
        XCTAssertNil(space.displayName)
        XCTAssertEqual(space.displayTitle, "feat/x")
        XCTAssertEqual(space.taskType, "feature")
        XCTAssertEqual(space.taskValue, "feat/x")
    }

    func testTrackedSpaceRoundTripUsesSnakeCase() throws {
        let space = TrackedSpace(
            projectName: "p", destination: "/tmp/p__feature-x", name: "p__feature-x",
            createdAt: "2026-07-10T12:34:56Z", taskType: "feature", taskValue: "feat/x")
        let yaml = try YAMLEncoder().encode(space)
        XCTAssertTrue(yaml.contains("project_name:"), yaml)
        XCTAssertTrue(yaml.contains("task_type:"), yaml)
        XCTAssertTrue(yaml.contains("created_at:"), yaml)
        XCTAssertFalse(yaml.contains("projectName"), yaml)
    }

    func testSpaceDisplayNameRoundTripsWithoutChangingTechnicalName() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbay-spaces-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        let space = TrackedSpace(
            projectName: "p", destination: "/tmp/p__feature-x", name: "p__feature-x",
            createdAt: "2026-07-10T12:34:56Z", taskType: "feature", taskValue: "feat/x")
        var store = try SpaceStore.load(url: url)
        try store.add(space)

        try store.rename(named: space.name, displayName: "Search feature")

        let renamed = try XCTUnwrap(SpaceStore.load(url: url).spaces.first)
        XCTAssertEqual(renamed.name, "p__feature-x")
        XCTAssertEqual(renamed.destination, "/tmp/p__feature-x")
        XCTAssertEqual(renamed.displayName, "Search feature")
        XCTAssertEqual(renamed.displayTitle, "Search feature")
        XCTAssertTrue(try String(contentsOf: url).contains("display_name: Search feature"))
    }
}
