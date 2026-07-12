import Foundation

/// Filesystem locations shared with the `orchestrate` Rust CLI. These must match
/// the CLI exactly so both tools read and write the same state.
public enum Paths {
    /// `~/Library/Application Support/com.jlex.orchestrate/settings.yaml`
    /// (matches the `directories` crate with qualifier `com`, org `jlex`, app `orchestrate`).
    public static var settingsFile: URL {
        applicationSupport
            .appendingPathComponent("com.jlex.orchestrate", isDirectory: true)
            .appendingPathComponent("settings.yaml", isDirectory: false)
    }

    /// `~/.orchestrate/spaces.yaml`
    public static var spacesFile: URL {
        home
            .appendingPathComponent(".orchestrate", isDirectory: true)
            .appendingPathComponent("spaces.yaml", isDirectory: false)
    }

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
