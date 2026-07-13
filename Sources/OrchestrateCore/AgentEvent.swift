import Foundation

/// An event received from an agent hook through the notifier socket, already
/// mapped to the three notified situations (decision n°7): turn ended, needs
/// input, or unknown (kept for diagnostics).
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Claude `UserPromptSubmit` hook: a turn begins, the agent is working.
        case turnStarted
        /// Claude `Stop` hook or Codex `agent-turn-complete`.
        case turnEnded
        /// Claude `Notification` hook (permission request / waiting for input).
        case needsInput
        case unknown(String)
    }

    public let sessionID: UUID
    public let kind: Kind
    /// Human message extracted from the hook payload, when available.
    public let message: String?

    public init(sessionID: UUID, kind: Kind, message: String? = nil) {
        self.sessionID = sessionID
        self.kind = kind
        self.message = message
    }

    /// Parses one notifier datagram: `{"session_id": …, "kind": …, "payload": …}`.
    public static func parse(_ data: Data) -> AgentEvent? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawID = root["session_id"] as? String,
            let sessionID = UUID(uuidString: rawID),
            let rawKind = root["kind"] as? String
        else { return nil }

        let payload = root["payload"] as? [String: Any]
        switch rawKind {
        case HookInjection.claudePromptKind:
            return AgentEvent(sessionID: sessionID, kind: .turnStarted)
        case HookInjection.claudeStopKind:
            return AgentEvent(sessionID: sessionID, kind: .turnEnded)
        case HookInjection.claudeNotificationKind:
            return AgentEvent(
                sessionID: sessionID, kind: .needsInput,
                message: payload?["message"] as? String)
        case HookInjection.codexNotifyKind:
            return AgentEvent(
                sessionID: sessionID, kind: .turnEnded,
                message: payload?["last-assistant-message"] as? String)
        default:
            return AgentEvent(sessionID: sessionID, kind: .unknown(rawKind))
        }
    }
}
