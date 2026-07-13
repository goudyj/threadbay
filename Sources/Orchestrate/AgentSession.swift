import AppKit
import Foundation
import OrchestrateCore
import SwiftTerm

/// One agent instance running (or finished) in an embedded terminal, tied to a
/// space. Owns the SwiftTerm view and its PTY — the view must outlive the
/// SwiftUI hierarchy so scrollback and process survive selection changes.
/// State moves through the `LocalProcessTerminalViewDelegate` callbacks.
@MainActor
final class AgentSession: NSObject, ObservableObject, Identifiable {
    enum State: Equatable {
        case starting
        case running
        case exited(Int32?)

        var isActive: Bool {
            switch self {
            case .starting, .running: return true
            case .exited: return false
            }
        }
    }

    /// Sticky "what happened last" marker driving badges and notifications;
    /// cleared when the user selects the session.
    enum Attention: Equatable {
        case none
        case turnEnded
        case needsInput
        case sessionEnded
    }

    nonisolated let id = UUID()
    let space: TrackedSpace
    let agent: AgentDefinition
    let startedAt = Date()
    let terminalView: SessionTerminalView

    @Published private(set) var state: State = .starting
    @Published var attention: Attention = .none
    /// Live "the agent is on a turn" flag (Claude `UserPromptSubmit` → `Stop`),
    /// unlike `attention` it is not sticky and never notifies.
    @Published var isWorking = false

    /// Installed by SessionManager; called on every state transition.
    var onStateChange: ((AgentSession) -> Void)?
    /// True when the exit was requested from the UI (then no notification).
    private(set) var stopRequested = false
    private var pendingRestart = false

    init(space: TrackedSpace, agent: AgentDefinition) {
        self.space = space
        self.agent = agent
        self.terminalView = SessionTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        terminalView.processDelegate = self
        configureAppearance()
    }

    // MARK: - Process control

    func start() {
        guard !terminalView.process.running else { return }
        stopRequested = false
        attention = .none
        state = .starting
        // The notifier identifies its session and finds the app through these.
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("ORCHESTRATE_SESSION_ID=\(id.uuidString)")
        environment.append("ORCHESTRATE_SOCK=\(Paths.eventSocket.path)")
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: launchArgs,
            environment: environment,
            currentDirectory: space.destination)
        state = .running
        onStateChange?(self)
    }

    /// Clean stop: SIGTERM for the agents, SIGHUP for interactive shells
    /// (which ignore SIGTERM), SIGKILL after a grace period if both were
    /// ignored. The PTY tears down on exit.
    func stop() {
        guard terminalView.process.running else { return }
        stopRequested = true
        let pid = terminalView.process.shellPid
        kill(pid, SIGTERM)
        kill(pid, SIGHUP)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.terminalView.process.running,
                self.terminalView.process.shellPid == pid
            else { return }
            kill(pid, SIGKILL)
        }
    }

    /// Restarts in place: waits for the current process to die (the PTY can
    /// only host one process at a time), then starts a fresh one.
    func restart() {
        if terminalView.process.running {
            pendingRestart = true
            stop()
        } else {
            start()
        }
    }

    /// Clears screen and scrollback (full emulator reset).
    func clear() {
        terminalView.getTerminal().resetToInitialState()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    // MARK: - Launch command

    /// A login shell resolves `claude`/`codex` exactly like a real terminal
    /// (no PATH guessing); `exec` keeps the agent as the PTY's direct child so
    /// signals and exit codes are its own. Empty command = interactive shell.
    private var launchArgs: [String] {
        var command = CommandTemplate.render(agent.command, space: space)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return ["-il"] }
        if agent.kind == .codex {
            // Per-process notify override; ~/.codex/config.toml stays untouched.
            let override = HookInjection.codexNotifyOverride(
                scriptPath: Paths.notifierScript.path)
            command += " -c \(override.shellQuoted)"
        }
        return ["-lc", "exec \(command)"]
    }

    private func configureAppearance() {
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        terminalView.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    }
}

// SwiftTerm invokes these on the main queue (LocalProcess's default).
extension AgentSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            state = .exited(exitCode)
            isWorking = false
            onStateChange?(self)
            if pendingRestart {
                pendingRestart = false
                start()
            }
        }
    }
}

/// Terminal view with ⌘V/⌘C wired directly, so copy/paste works even when the
/// menu-bar app exposes no Edit menu.
final class SessionTerminalView: LocalProcessTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
            event.modifierFlags.isDisjoint(with: [.option, .control]) {
            switch event.charactersIgnoringModifiers {
            case "v":
                paste(self)
                return true
            case "c":
                copy(self)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
