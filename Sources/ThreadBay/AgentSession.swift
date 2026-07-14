import AppKit
import Carbon.HIToolbox
import Foundation
import ThreadBayCore
import SwiftTerm

enum TerminalTheme: String {
    case system
    case light
    case dark

    func colors(for appearance: NSAppearance) -> (background: NSColor, foreground: NSColor) {
        let isDark: Bool
        switch self {
        case .system:
            isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        case .light:
            isDark = false
        case .dark:
            isDark = true
        }

        if isDark {
            return (
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1),
                NSColor(calibratedWhite: 0.92, alpha: 1))
        }
        return (
            NSColor(calibratedWhite: 0.98, alpha: 1),
            NSColor(calibratedWhite: 0.12, alpha: 1))
    }
}

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
    private(set) var space: TrackedSpace
    let agent: AgentDefinition
    let startedAt = Date()
    let terminalView: SessionTerminalView
    private let notifierPath: String?

    @Published private(set) var state: State = .starting
    @Published var attention: Attention = .none
    /// Live "the agent is on a turn" flag (Claude `UserPromptSubmit` → `Stop`),
    /// unlike `attention` it is not sticky and never notifies.
    @Published var isWorking = false

    /// Installed by SessionManager; called on every state transition.
    var onStateChange: ((AgentSession) -> Void)?
    /// True when the exit was requested from the UI (then no notification).
    private(set) var stopRequested = false

    init(
        space: TrackedSpace,
        agent: AgentDefinition,
        notifierPath: String?,
        theme: TerminalTheme = .system
    ) {
        self.space = space
        self.agent = agent
        self.notifierPath = notifierPath
        self.terminalView = SessionTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        applyTheme(theme)
    }

    // MARK: - Process control

    func start() {
        guard !terminalView.process.running else { return }
        stopRequested = false
        attention = .none
        state = .starting
        // The notifier identifies its session and finds the app through these.
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("THREADBAY_SESSION_ID=\(id.uuidString)")
        environment.append("THREADBAY_SOCK=\(Paths.eventSocket.path)")
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

    func updateSpace(_ space: TrackedSpace) {
        guard self.space.name == space.name else { return }
        self.space = space
    }

    // MARK: - Launch command

    /// A login shell resolves `claude`/`codex` exactly like a real terminal
    /// (no PATH guessing); `exec` keeps the agent as the PTY's direct child so
    /// signals and exit codes are its own. Empty command = interactive shell.
    private var launchArgs: [String] {
        var command = CommandTemplate.render(agent.command, space: space)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return ["-il"] }
        if agent.kind == .codex, let notifierPath {
            // Per-process notify override; ~/.codex/config.toml stays untouched.
            let override = HookInjection.codexNotifyOverride(
                notifierPath: notifierPath)
            command += " -c \(override.shellQuoted)"
        }
        return ["-lc", "exec \(command)"]
    }

    func applyTheme(_ theme: TerminalTheme) {
        terminalView.applyTheme(theme)
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
        }
    }
}

/// Adds macOS terminal conventions that SwiftTerm does not handle itself.
class SessionTerminalView: LocalProcessTerminalView {
    private var theme: TerminalTheme = .system

    func applyTheme(_ theme: TerminalTheme) {
        self.theme = theme
        let colors = theme.colors(for: effectiveAppearance)
        nativeBackgroundColor = colors.background
        nativeForegroundColor = colors.foreground
        setNeedsDisplay(bounds)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard theme == .system else { return }
        applyTheme(theme)
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        let kittyKeyboardEnabled = !getTerminal().keyboardEnhancementFlags.isEmpty
        guard let bytes = Self.terminalInput(
            for: event,
            kittyKeyboardEnabled: kittyKeyboardEnabled
        ) else { return false }
        send(source: self, data: bytes[...])
        return true
    }

    private static func terminalInput(
        for event: NSEvent,
        kittyKeyboardEnabled: Bool
    ) -> [UInt8]? {
        let modifiers = event.modifierFlags.intersection([
            .command, .control, .option, .shift,
        ])
        if event.keyCode == UInt16(kVK_Return), modifiers == .shift {
            // SwiftTerm preserves Shift itself once the application enables
            // Kitty; otherwise use Ghostty's legacy modified-key sequence.
            guard !kittyKeyboardEnabled else { return nil }
            return Array("\u{1b}[27;2;13~".utf8)
        }
        if event.keyCode == UInt16(kVK_Delete), modifiers == .command {
            return [0x15] // Ctrl+U: delete to start of line
        }
        return nil
    }

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
