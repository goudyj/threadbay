import Foundation
import Yams

/// Reads and writes `settings.yaml`, the file the CLI manages (`src/settings.rs`).
/// All fields are round-tripped so app writes never drop CLI-only config.
public struct Settings: Codable, Sendable {
    public var defaultProject: String?
    public var projects: [Project]
    public var agentCommands: AgentCommands

    public init(
        defaultProject: String? = nil,
        projects: [Project] = [],
        agentCommands: AgentCommands = AgentCommands()
    ) {
        self.defaultProject = defaultProject
        self.projects = projects
        self.agentCommands = agentCommands
    }

    enum CodingKeys: String, CodingKey {
        case defaultProject = "default_project"
        case projects
        case agentCommands = "agent_commands"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultProject = try c.decodeIfPresent(String.self, forKey: .defaultProject)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        agentCommands = try c.decodeIfPresent(AgentCommands.self, forKey: .agentCommands)
            ?? AgentCommands()
    }

    public func project(named name: String) -> Project? {
        projects.first { $0.name == name }
    }

    // MARK: - Persistence

    /// Loads settings, creating an empty file if none exists (matches CLI behaviour).
    public static func load() throws -> Settings {
        let url = Paths.settingsFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            let empty = Settings()
            try empty.save()
            return empty
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(Settings.self, from: text)
    }

    public func save() throws {
        let url = Paths.settingsFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
