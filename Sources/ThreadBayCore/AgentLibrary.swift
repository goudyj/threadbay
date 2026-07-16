import Foundation
import Yams

/// An agent the app can launch inside an embedded terminal, tied to a space.
public struct AgentDefinition: Codable, Identifiable, Hashable, Sendable {
    /// Drives agent-specific behaviour at launch (hook / notify injection).
    public enum Kind: String, Codable, Sendable {
        case claude
        case codex
        case shell
        case custom
    }

    public var name: String
    /// Command template run through a login shell in the space directory.
    /// Supports placeholders (see `CommandTemplate`). Empty means "interactive shell".
    public var command: String
    public var kind: Kind

    public var id: String { name }

    public init(name: String, command: String, kind: Kind = .custom) {
        self.name = name
        self.command = command
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .custom
    }
}

/// A non-interactive command that reads commit context from stdin and writes a
/// proposed commit message to stdout.
public struct CommitGeneratorDefinition: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var command: String

    public var id: String { name }

    public init(name: String, command: String) {
        self.name = name
        self.command = command
    }
}

/// Reads and writes `agents.yaml`, the app-only agent catalogue. Kept out of
/// `settings.yaml` because the Rust CLI drops unknown keys when it rewrites it.
public struct AgentLibrary: Codable, Sendable {
    public var agents: [AgentDefinition]
    public var commitGenerators: [CommitGeneratorDefinition]

    public init(
        agents: [AgentDefinition],
        commitGenerators: [CommitGeneratorDefinition] = []
    ) {
        self.agents = agents
        self.commitGenerators = commitGenerators
    }

    enum CodingKeys: String, CodingKey {
        case agents
        case commitGenerators = "commit_generators"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = try c.decodeIfPresent([AgentDefinition].self, forKey: .agents) ?? []
        commitGenerators = try c.decodeIfPresent(
            [CommitGeneratorDefinition].self, forKey: .commitGenerators) ?? []
    }

    /// Agents shipped by default on first launch.
    public static let defaults = AgentLibrary(agents: [
        AgentDefinition(name: "Claude", command: "claude", kind: .claude),
        AgentDefinition(name: "Codex", command: "codex", kind: .codex),
        AgentDefinition(name: "Shell", command: "", kind: .shell),
    ])

    /// Loads the library, creating the file with the defaults if it is missing.
    public static func load(url: URL = Paths.agentsFile) throws -> AgentLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let library = defaults
            try library.save(url: url)
            return library
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(AgentLibrary.self, from: text)
    }

    public func save(url: URL = Paths.agentsFile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Renders the `{placeholder}` variables of an agent command for a given space.
public enum CommandTemplate {
    /// Supported placeholders, shown in the agent editor UI.
    public static let placeholders = [
        "{space_path}", "{branch}", "{task_value}", "{name}", "{project}",
    ]

    public static func render(
        _ template: String,
        space: TrackedSpace,
        currentBranch: String? = nil
    ) -> String {
        template
            .replacingOccurrences(of: "{space_path}", with: space.destination)
            .replacingOccurrences(of: "{branch}", with: currentBranch ?? space.taskValue)
            .replacingOccurrences(of: "{task_value}", with: space.taskValue)
            .replacingOccurrences(of: "{name}", with: space.name)
            .replacingOccurrences(of: "{project}", with: space.projectName)
    }
}

extension String {
    /// The string wrapped in single quotes for safe interpolation in `zsh -c`.
    public var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
