import Foundation

/// A configured project. Mirrors the CLI's `Project` (`src/settings.rs`).
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var path: String
    public var filesToInclude: [String]

    public var id: String { name }

    public init(name: String, path: String, filesToInclude: [String] = []) {
        self.name = name
        self.path = path
        self.filesToInclude = filesToInclude
    }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case filesToInclude = "files_to_include"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        filesToInclude = try c.decodeIfPresent([String].self, forKey: .filesToInclude) ?? []
    }
}

/// A branch together with the repository location it came from. Keeping this
/// provenance avoids silently treating a diverged local and remote branch as
/// the same checkout target.
public struct GitBranch: Identifiable, Hashable, Sendable {
    public enum Location: Hashable, Sendable {
        case local
        case remote(String)
    }

    public let name: String
    public let location: Location

    public var id: String {
        switch location {
        case .local:
            return "local:\(name)"
        case .remote(let remote):
            return "remote:\(remote)/\(name)"
        }
    }

    public var referenceName: String {
        switch location {
        case .local:
            return name
        case .remote(let remote):
            return "\(remote)/\(name)"
        }
    }

    public init(name: String, location: Location) {
        self.name = name
        self.location = location
    }
}

/// The space creation flows exposed by the macOS app.
public enum SpaceCreation: Hashable, Sendable {
    case feature(branchName: String, base: GitBranch)
    case existingBranch(GitBranch)
    case pullRequest(UInt)
    case folder(name: String)
}

/// Optional per-task agent commands. Preserved on round-trip even though the app
/// does not use them, so saving settings from the app never drops CLI config.
public struct AgentCommands: Codable, Hashable, Sendable {
    public var review: String?
    public var feature: String?

    public init(review: String? = nil, feature: String? = nil) {
        self.review = review
        self.feature = feature
    }
}

/// A tracked space entry. Mirrors the CLI's `TrackedSpace` (`src/tracking.rs`).
public struct TrackedSpace: Codable, Identifiable, Hashable, Sendable {
    public var projectName: String
    public var destination: String
    public var name: String
    public var displayName: String?
    public var createdAt: String
    public var taskType: String
    public var taskValue: String

    public var id: String { name }
    public var displayTitle: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }

    public init(
        projectName: String,
        destination: String,
        name: String,
        displayName: String? = nil,
        createdAt: String,
        taskType: String,
        taskValue: String
    ) {
        self.projectName = projectName
        self.destination = destination
        self.name = name
        self.displayName = displayName
        self.createdAt = createdAt
        self.taskType = taskType
        self.taskValue = taskValue
    }

    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case destination
        case name
        case displayName = "display_name"
        case createdAt = "created_at"
        case taskType = "task_type"
        case taskValue = "task_value"
    }
}
