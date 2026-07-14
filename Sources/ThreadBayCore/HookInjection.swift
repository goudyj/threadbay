import Foundation

/// Non-invasive wiring of agent hooks to the app (decision n°9): the user's
/// global `~/.claude` / `~/.codex` config is never touched. Claude gets a
/// `.claude/settings.local.json` written *inside the space* (a throwaway clone);
/// Codex gets a per-process `-c notify=…` override. Both call the notifier
/// script, which forwards `{session_id, kind, payload}` to the app's Unix
/// socket and is a no-op when the app is not running.
public enum HookInjection {
    /// Event kinds emitted by the notifier script (its first argument).
    public static let claudePromptKind = "claude-prompt"
    public static let claudeStopKind = "claude-stop"
    public static let claudeNotificationKind = "claude-notification"
    public static let codexNotifyKind = "codex-notify"

    /// POSIX-sh notifier. Payload JSON arrives on stdin (Claude hooks) or as
    /// the second argument (Codex notify).
    public static let notifierScript = """
        #!/bin/sh
        # ThreadBay notifier - forwards agent events to the app's Unix socket.
        # Usage: threadbay-notify.sh <kind>            (payload JSON on stdin)
        #        threadbay-notify.sh <kind> <payload>  (payload JSON as argument)
        # No-op when the ThreadBay app is not running (socket absent).
        [ -n "$THREADBAY_SOCK" ] && [ -S "$THREADBAY_SOCK" ] || exit 0
        if [ "$#" -ge 2 ]; then payload="$2"; else payload="$(cat 2>/dev/null)"; fi
        [ -n "$payload" ] || payload=null
        printf '{"session_id":"%s","kind":"%s","payload":%s}' \\
            "$THREADBAY_SESSION_ID" "${1:-unknown}" "$payload" \\
            | /usr/bin/nc -U "$THREADBAY_SOCK" -w 2 >/dev/null 2>&1
        exit 0
        """

    /// Writes the notifier script (idempotent) and returns its path.
    @discardableResult
    public static func installNotifier(at url: URL = Paths.notifierScript) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? String(contentsOf: url, encoding: .utf8)) != notifierScript {
            try notifierScript.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Merges the ThreadBay `Stop` / `Notification` hooks into an existing
    /// `.claude/settings.local.json` payload (or creates one). Only those two
    /// keys are overwritten; the rest of the file is preserved.
    public static func claudeSettings(merging existing: Data?, scriptPath: String) throws -> Data {
        var root: [String: Any] = [:]
        if let existing,
            let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            root = parsed
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // UserPromptSubmit marks the turn start ("agent is working").
        hooks["UserPromptSubmit"] = [hookEntry(scriptPath: scriptPath, kind: claudePromptKind)]
        hooks["Stop"] = [hookEntry(scriptPath: scriptPath, kind: claudeStopKind)]
        hooks["Notification"] = [hookEntry(scriptPath: scriptPath, kind: claudeNotificationKind)]
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes (merging) `.claude/settings.local.json` inside the space directory.
    public static func injectClaudeHooks(spaceDir: URL, scriptPath: String) throws {
        let dir = spaceDir.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.local.json", isDirectory: false)
        let existing = try? Data(contentsOf: file)
        let merged = try claudeSettings(merging: existing, scriptPath: scriptPath)
        try merged.write(to: file, options: .atomic)
    }

    /// The `-c notify=…` override appended to a Codex launch (per-process, so
    /// `~/.codex/config.toml` is left untouched).
    public static func codexNotifyOverride(scriptPath: String) -> String {
        "notify=[\"\(scriptPath)\",\"\(codexNotifyKind)\"]"
    }

    private static func hookEntry(scriptPath: String, kind: String) -> [String: Any] {
        [
            "hooks": [
                ["type": "command", "command": "\(scriptPath.shellQuoted) \(kind)"]
            ]
        ]
    }
}
