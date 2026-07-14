import Foundation

/// Filesystem locations shared with the `threadbay` Rust CLI in production.
/// Development builds use a separate namespace so they cannot mutate live data.
public enum Paths {
    public static var settingsFile: URL {
        currentLocations.settingsFile
    }

    public static var spacesFile: URL {
        currentLocations.spacesFile
    }

    /// App-only agent definitions — deliberately a separate file so the Rust CLI
    /// never rewrites (and drops) it when saving `settings.yaml`.
    public static var agentsFile: URL {
        currentLocations.agentsFile
    }

    /// Unix domain socket the app listens on for agent hook events.
    public static var eventSocket: URL {
        currentLocations.eventSocket
    }

    public static var appDirectory: URL {
        currentLocations.appDirectory
    }

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    struct Locations: Equatable {
        let settingsFile: URL
        let spacesFile: URL
        let agentsFile: URL
        let eventSocket: URL
        let appDirectory: URL
    }

    static func locations(
        environment: AppEnvironment,
        home: URL,
        applicationSupport: URL
    ) -> Locations {
        let appDirectory = applicationSupport.appendingPathComponent(
            environment.appDirectoryName, isDirectory: true)
        return Locations(
            settingsFile: appDirectory.appendingPathComponent("settings.yaml"),
            spacesFile: home
                .appendingPathComponent(environment.spacesDirectoryName, isDirectory: true)
                .appendingPathComponent("spaces.yaml"),
            agentsFile: appDirectory.appendingPathComponent("agents.yaml"),
            eventSocket: appDirectory.appendingPathComponent("threadbay.sock"),
            appDirectory: appDirectory)
    }

    private static var currentLocations: Locations {
        locations(
            environment: AppEnvironment.current,
            home: home,
            applicationSupport: applicationSupport)
    }
}
