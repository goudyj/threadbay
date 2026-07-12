import Foundation
import Yams

/// Reads and writes `spaces.yaml`, the tracking registry the CLI manages
/// (`src/tracking.rs`). Shape: `{ spaces: [TrackedSpace] }`.
public struct SpaceStore: Sendable {
    public private(set) var spaces: [TrackedSpace]
    private let url: URL

    private struct Registry: Codable {
        var spaces: [TrackedSpace]
    }

    private init(spaces: [TrackedSpace], url: URL) {
        self.spaces = spaces
        self.url = url
    }

    public static func load(url: URL = Paths.spacesFile) throws -> SpaceStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SpaceStore(spaces: [], url: url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let registry = try YAMLDecoder().decode(Registry.self, from: text)
        return SpaceStore(spaces: registry.spaces, url: url)
    }

    public mutating func add(_ space: TrackedSpace) throws {
        spaces.append(space)
        try save()
    }

    public func space(named name: String) -> TrackedSpace? {
        spaces.first { $0.name == name }
    }

    /// Removes the entry by name and persists. No-op if it is already absent.
    public mutating func remove(named name: String) throws {
        spaces.removeAll { $0.name == name }
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(Registry(spaces: spaces))
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
