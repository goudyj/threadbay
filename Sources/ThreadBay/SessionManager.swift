import Foundation
import ThreadBayCore

/// Source of truth for agent sessions (decision n°2: several per space). Owns
/// the event socket the notifier executable talks to, maps `session_id` back to a
/// session, and posts macOS notifications for the three notified situations.
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published var selectedID: UUID?

    /// Installed by AppState to surface launch errors in the UI.
    var onError: ((Error) -> Void)?
    /// Installed by AppState; brings the window up and selects a space.
    var onFocusSession: ((AgentSession) -> Void)?

    let notifications = NotificationService()
    private var socketServer: EventSocketServer?
    private var terminalTheme: TerminalTheme = .system
    private var language: AppLanguage = .system

    var selected: AgentSession? {
        sessions.first { $0.id == selectedID }
    }

    func sessions(for space: TrackedSpace) -> [AgentSession] {
        sessions.filter { $0.space.name == space.name }
    }

    func runningCount(for space: TrackedSpace) -> Int {
        sessions(for: space).filter { $0.state.isActive }.count
    }

    func needsAttention(_ space: TrackedSpace) -> Bool {
        sessions(for: space).contains { $0.attention == .needsInput }
    }

    func isWorking(_ space: TrackedSpace) -> Bool {
        sessions(for: space).contains(where: \.isWorking)
    }

    var runningCount: Int {
        sessions.filter { $0.state.isActive }.count
    }

    // MARK: - Lifecycle

    /// Starts the Unix-socket event server and the notification service.
    func setUp() {
        notifications.setup()
        notifications.onSelectSession = { [weak self] id in
            guard let self, let session = self.sessions.first(where: { $0.id == id }) else {
                return
            }
            self.focus(session)
        }
        do {
            let server = EventSocketServer(path: Paths.eventSocket.path) { [weak self] data in
                guard let event = AgentEvent.parse(data) else { return }
                Task { @MainActor in self?.handle(event) }
            }
            try server.start()
            socketServer = server
        } catch {
            // Hooks become no-ops without the socket; channel 1 (process end)
            // still works, so this is not fatal.
            onError?(error)
        }
    }

    func tearDown() {
        stopAll()
        socketServer?.stop()
        socketServer = nil
    }

    // MARK: - Session control

    func launch(
        agent: AgentDefinition,
        in space: TrackedSpace,
        currentBranch: String? = nil
    ) {
        do {
            let notifierPath: String?
            if agent.kind == .claude || agent.kind == .codex {
                notifierPath = try Self.notifierExecutable().path
            } else {
                notifierPath = nil
            }
            if agent.kind == .claude, let notifierPath {
                try HookInjection.injectClaudeHooks(
                    spaceDir: URL(fileURLWithPath: space.destination),
                    notifierPath: notifierPath)
            }
            let session = AgentSession(
                space: space,
                agent: agent,
                currentBranch: currentBranch,
                notifierPath: notifierPath,
                theme: terminalTheme)
            session.onStateChange = { [weak self] session in
                self?.sessionChanged(session)
            }
            sessions.append(session)
            select(session.id)
            session.start()
        } catch {
            onError?(error)
        }
    }

    /// Stops the process (if needed) and removes the session and its terminal.
    func close(_ session: AgentSession) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id {
            selectedID = sessions.first(where: { $0.space.name == session.space.name })?.id
        }
    }

    /// Called before a space is deleted: its agents must not outlive the folder.
    func closeSessions(for space: TrackedSpace) {
        for session in sessions(for: space) {
            close(session)
        }
    }

    func updateSpace(_ space: TrackedSpace) {
        sessions(for: space).forEach { $0.updateSpace(space) }
        objectWillChange.send()
    }

    func stopAll() {
        for session in sessions {
            session.stop()
        }
    }

    func setTerminalTheme(_ theme: TerminalTheme) {
        terminalTheme = theme
        sessions.forEach { $0.applyTheme(theme) }
        objectWillChange.send()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        objectWillChange.send()
    }

    /// Selecting a session acknowledges its badge.
    func select(_ id: UUID?) {
        selectedID = id
        if let session = sessions.first(where: { $0.id == id }) {
            acknowledge(session)
        }
        // Views observing the manager (sidebar badges) read session state.
        objectWillChange.send()
    }

    /// Clears a session's badge once its terminal is visible in the key
    /// window: seeing the terminal is taking note of the notification.
    func acknowledge(_ session: AgentSession) {
        guard session.attention != .none else { return }
        session.attention = .none
        objectWillChange.send()
    }

    private func focus(_ session: AgentSession) {
        select(session.id)
        onFocusSession?(session)
    }

    // MARK: - Events

    /// Channel 3 (hooks) — the semantic signal.
    private func handle(_ event: AgentEvent) {
        guard let session = sessions.first(where: { $0.id == event.sessionID }) else { return }
        objectWillChange.send()
        switch event.kind {
        case .turnStarted:
            // Live indicator only: no badge to acknowledge, no notification.
            session.isWorking = true
        case .turnEnded:
            session.isWorking = false
            session.attention = .turnEnded
            notifications.post(
                title: localized("notification.turn_completed", session.displayName),
                body: event.message ?? session.space.displayTitle,
                sessionID: session.id)
        case .needsInput:
            // The agent is paused on a question, not computing.
            session.isWorking = false
            session.attention = .needsInput
            notifications.post(
                title: localized("notification.needs_input", session.displayName),
                body: event.message ?? session.space.displayTitle,
                sessionID: session.id)
        case .unknown:
            break
        }
    }

    /// Channel 1 (process end) — the safety net.
    private func sessionChanged(_ session: AgentSession) {
        objectWillChange.send()
        guard case .exited(let code) = session.state, !session.stopRequested else { return }
        session.attention = .sessionEnded
        let detail = code.map { localized("notification.exit_code", $0) } ?? ""
        notifications.post(
            title: localized("notification.session_ended", session.displayName, detail),
            body: session.space.displayTitle,
            sessionID: session.id)
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: language, arguments: arguments)
    }

    private static func notifierExecutable() throws -> URL {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("threadbay-notify", isDirectory: false)
        let swiftPMBuild = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("ThreadBayNotify", isDirectory: false)
        let candidates = [bundled, swiftPMBuild].compactMap { $0 }
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw NotifierExecutableError.notFound
        }
        return executable
    }

    private enum NotifierExecutableError: LocalizedError {
        case notFound

        var errorDescription: String? {
            "The ThreadBay notifier executable is missing. Rebuild the application."
        }
    }
}
