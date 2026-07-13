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

    /// `~/Library/Application Support/com.jlex.orchestrate/agents.yaml`
    /// App-only agent definitions — deliberately a separate file so the Rust CLI
    /// never rewrites (and drops) it when saving `settings.yaml`.
    public static var agentsFile: URL {
        appDirectory.appendingPathComponent("agents.yaml", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.orchestrate/orchestrate.sock`
    /// Unix domain socket the app listens on for agent hook events.
    public static var eventSocket: URL {
        appDirectory.appendingPathComponent("orchestrate.sock", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.orchestrate/orchestrate-notify.sh`
    /// Notifier script injected into agent hooks; forwards events to the socket.
    public static var notifierScript: URL {
        appDirectory.appendingPathComponent("orchestrate-notify.sh", isDirectory: false)
    }

    /// `~/Library/Application Support/com.jlex.orchestrate/`
    public static var appDirectory: URL {
        applicationSupport.appendingPathComponent("com.jlex.orchestrate", isDirectory: true)
    }

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
