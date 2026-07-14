import Foundation

/// Filesystem locations shared with the `threadbay` Rust CLI. These must match
/// the CLI exactly so both tools read and write the same state.
public enum Paths {
    /// `~/Library/Application Support/com.jlex.threadbay/settings.yaml`
    /// (matches the `directories` crate with qualifier `com`, org `jlex`, app `threadbay`).
    public static var settingsFile: URL {
        applicationSupport
            .appendingPathComponent("com.jlex.threadbay", isDirectory: true)
            .appendingPathComponent("settings.yaml", isDirectory: false)
    }

    /// `~/.threadbay/spaces.yaml`
    public static var spacesFile: URL {
        home
            .appendingPathComponent(".threadbay", isDirectory: true)
            .appendingPathComponent("spaces.yaml", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.threadbay/agents.yaml`
    /// App-only agent definitions — deliberately a separate file so the Rust CLI
    /// never rewrites (and drops) it when saving `settings.yaml`.
    public static var agentsFile: URL {
        appDirectory.appendingPathComponent("agents.yaml", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.threadbay/threadbay.sock`
    /// Unix domain socket the app listens on for agent hook events.
    public static var eventSocket: URL {
        appDirectory.appendingPathComponent("threadbay.sock", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.threadbay/`
    public static var appDirectory: URL {
        applicationSupport.appendingPathComponent("com.jlex.threadbay", isDirectory: true)
    }

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
