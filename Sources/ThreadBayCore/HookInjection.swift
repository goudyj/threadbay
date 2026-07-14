import Foundation

/// Non-invasive wiring of agent hooks to the app (decision n°9): the user's
/// global `~/.claude` / `~/.codex` config is never touched. Claude gets a
/// `.claude/settings.local.json` written *inside the space* (a throwaway clone);
/// Codex gets a per-process `-c notify=…` override. Both call the notifier
/// executable, which forwards `{session_id, kind, payload}` to the app's Unix
/// socket and is a no-op when the app is not running.
public enum HookInjection {
    /// Event kinds emitted by the notifier executable (its first argument).
    public static let claudePromptKind = "claude-prompt"
    public static let claudeStopKind = "claude-stop"
    public static let claudeNotificationKind = "claude-notification"
    public static let codexNotifyKind = "codex-notify"

    /// Merges the ThreadBay `Stop` / `Notification` hooks into an existing
    /// `.claude/settings.local.json` payload (or creates one). Only those two
    /// keys are overwritten; the rest of the file is preserved.
    public static func claudeSettings(
        merging existing: Data?, notifierPath: String
    ) throws -> Data {
        var root: [String: Any] = [:]
        if let existing,
            let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            root = parsed
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // UserPromptSubmit marks the turn start ("agent is working").
        hooks["UserPromptSubmit"] = [
            hookEntry(notifierPath: notifierPath, kind: claudePromptKind)
        ]
        hooks["Stop"] = [hookEntry(notifierPath: notifierPath, kind: claudeStopKind)]
        hooks["Notification"] = [
            hookEntry(notifierPath: notifierPath, kind: claudeNotificationKind)
        ]
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes (merging) `.claude/settings.local.json` inside the space directory.
    public static func injectClaudeHooks(spaceDir: URL, notifierPath: String) throws {
        let dir = spaceDir.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.local.json", isDirectory: false)
        let existing = try? Data(contentsOf: file)
        let merged = try claudeSettings(merging: existing, notifierPath: notifierPath)
        try merged.write(to: file, options: .atomic)
    }

    /// The `-c notify=…` override appended to a Codex launch (per-process, so
    /// `~/.codex/config.toml` is left untouched).
    public static func codexNotifyOverride(notifierPath: String) -> String {
        "notify=[\"\(notifierPath)\",\"\(codexNotifyKind)\"]"
    }

    private static func hookEntry(notifierPath: String, kind: String) -> [String: Any] {
        [
            "hooks": [
                ["type": "command", "command": "\(notifierPath.shellQuoted) \(kind)"]
            ]
        ]
    }
}
