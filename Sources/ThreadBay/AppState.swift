import AppKit
import Foundation
import ThreadBayCore
import SwiftUI

/// Observable app state: loads settings + tracked spaces and exposes the actions
/// wired to the UI. All blocking work (git, editors) runs off the main actor.
@MainActor
final class AppState: ObservableObject {
    private static let terminalThemeKey = "terminalTheme"
    private static let appLanguageKey = "appLanguage"

    @Published var settings = Settings()
    @Published var spaces: [TrackedSpace] = []
    @Published var agents: [AgentDefinition] = []
    @Published private(set) var shortcuts: AppShortcutSettings
    @Published private(set) var terminalTheme: TerminalTheme
    @Published private(set) var appLanguage: AppLanguage
    @Published var errorMessage: String?
    @Published var isBusy = false

    /// Set by the menu bar to ask the window to present the create sheet.
    @Published var pendingNewSpace = false
    @Published var pendingSettings = false
    /// Asks the window to select a space (set when launching an agent).
    @Published var pendingSelectSpace: String?
    @Published var selectedSpaceName = ""
    @Published var pendingCloseSessionID: UUID?

    /// Installed by the app delegate; brings the main window to the front.
    var onShowWindow: (@MainActor () -> Void)?

    let sessionManager = SessionManager()

    func showMainWindow() {
        onShowWindow?()
    }

    private let spaceService = SpaceService()
    private let gitService = GitService()
    private let githubService = GitHubService()
    private let openService = OpenService()

    init() {
        shortcuts = AppShortcutSettings.load()
        appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? ""
        ) ?? .system
        terminalTheme = TerminalTheme(
            rawValue: UserDefaults.standard.string(forKey: Self.terminalThemeKey) ?? ""
        ) ?? .system
        reload()
        sessionManager.setLanguage(appLanguage)
        sessionManager.setTerminalTheme(terminalTheme)
        sessionManager.onError = { [weak self] error in
            self?.errorMessage = self?.localizedError(error)
        }
        sessionManager.onFocusSession = { [weak self] session in
            self?.pendingSelectSpace = session.space.name
            self?.showMainWindow()
        }
    }

    struct ProjectGroup: Identifiable {
        let id: String
        let spaces: [TrackedSpace]
    }

    var groups: [ProjectGroup] {
        Dictionary(grouping: spaces, by: \.projectName)
            .map { ProjectGroup(id: $0.key, spaces: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Loading

    func reload() {
        do {
            settings = try Settings.load()
            spaces = try SpaceStore.load().spaces
            agents = try AgentLibrary.load().agents
        } catch {
            errorMessage = localizedError(error)
        }
    }

    // MARK: - Git queries (for the create form)

    func listBranches(project: Project) async -> [GitBranch] {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { (try? git.listBranches(repo: repo)) ?? [] }.value
    }

    func refreshBranches(project: Project) async -> [GitBranch]? {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        do {
            return try await Task.detached { try git.refreshBranches(repo: repo) }.value
        } catch {
            errorMessage = localizedError(error)
            return nil
        }
    }

    func currentBranch(project: Project) async -> String? {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { git.currentBranch(repo: repo) }.value
    }

    // MARK: - GitHub queries (for the pull-request selector)

    func listPullRequests(project: Project) async -> [PullRequestSummary]? {
        let github = githubService
        let repo = URL(fileURLWithPath: project.path)
        do {
            return try await Task.detached {
                try github.listOpenPullRequests(repo: repo)
            }.value
        } catch {
            errorMessage = localizedError(error)
            return nil
        }
    }

    /// Exact-number lookups are speculative while the user types, so an
    /// unknown PR is an empty result rather than a global error alert.
    func pullRequest(project: Project, number: UInt) async -> PullRequestSummary? {
        let github = githubService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached {
            try? github.pullRequest(number: number, repo: repo)
        }.value
    }

    // MARK: - Mutations

    /// Returns true on success. On failure sets `errorMessage`.
    func createSpace(project: Project, creation: SpaceCreation) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        let service = spaceService
        do {
            _ = try await Task.detached {
                try service.create(project: project, creation: creation)
            }.value
            reload()
            return true
        } catch {
            errorMessage = localizedError(error)
            return false
        }
    }

    func delete(_ space: TrackedSpace) {
        // Agents must not outlive the folder they run in.
        sessionManager.closeSessions(for: space)
        let service = spaceService
        Task {
            do {
                try await Task.detached { try service.delete(space) }.value
                reload()
            } catch {
                errorMessage = localizedError(error)
            }
        }
    }

    // MARK: - Agents

    func launchAgent(_ agent: AgentDefinition, in space: TrackedSpace) {
        sessionManager.launch(agent: agent, in: space)
        pendingSelectSpace = space.name
        showMainWindow()
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        guard let action = shortcuts.action(matching: event) else { return false }
        guard !event.isARepeat else { return true }

        switch action {
        case .newSpace:
            pendingNewSpace = true
            showMainWindow()
        case .closeSession:
            requestCloseActiveSession()
        case .launchClaude:
            launchAgent(kind: .claude)
        case .launchCodex:
            launchAgent(kind: .codex)
        case .launchShell:
            launchAgent(kind: .shell)
        }
        return true
    }

    func setShortcut(_ shortcut: AppShortcut, for action: AppShortcutAction) {
        guard shortcuts.conflictingAction(for: shortcut, excluding: action) == nil else {
            errorMessage = localized("settings.shortcut_conflict", shortcut.displayName)
            return
        }
        shortcuts[action] = shortcut
        shortcuts.save()
    }

    func resetShortcuts() {
        shortcuts = AppShortcutSettings()
        shortcuts.save()
    }

    var pendingCloseSession: AgentSession? {
        guard let pendingCloseSessionID else { return nil }
        return sessionManager.sessions.first { $0.id == pendingCloseSessionID }
    }

    func confirmCloseSession() {
        guard let session = pendingCloseSession else { return }
        sessionManager.close(session)
        pendingCloseSessionID = nil
    }

    func cancelCloseSession() {
        pendingCloseSessionID = nil
    }

    func persistAgents() {
        do {
            try AgentLibrary(agents: agents).save()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    private func requestCloseActiveSession() {
        guard let space = spaces.first(where: { $0.name == selectedSpaceName }) else { return }
        let sessions = sessionManager.sessions(for: space)
        let active = sessions.first { $0.id == sessionManager.selectedID } ?? sessions.first
        pendingCloseSessionID = active?.id
    }

    private func launchAgent(kind: AgentDefinition.Kind) {
        guard let space = spaces.first(where: { $0.name == selectedSpaceName }),
            let agent = agents.first(where: { $0.kind == kind })
        else { return }
        launchAgent(agent, in: space)
    }

    func setTerminalTheme(_ theme: TerminalTheme) {
        terminalTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.terminalThemeKey)
        sessionManager.setTerminalTheme(theme)
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.appLanguageKey)
        sessionManager.setLanguage(language)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: appLanguage, arguments: arguments)
    }

    // MARK: - Open actions

    func open(_ editor: Editor, _ space: TrackedSpace) {
        let service = openService
        let path = space.destination
        Task {
            do {
                try await Task.detached { try service.open(editor, at: path) }.value
            } catch {
                errorMessage = localizedError(error)
            }
        }
    }

    func reveal(_ space: TrackedSpace) {
        let service = openService
        let path = space.destination
        Task {
            do {
                try await Task.detached { try service.revealInFinder(path) }.value
            } catch {
                errorMessage = localizedError(error)
            }
        }
    }

    // MARK: - Settings management

    func persistSettings() {
        do {
            try settings.save()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func addProject(path: URL) {
        let name = path.lastPathComponent
        guard !settings.projects.contains(where: { $0.name == name }) else {
            errorMessage = localized("error.project_exists", name)
            return
        }
        settings.projects.append(Project(name: name, path: path.path))
        if settings.defaultProject == nil {
            settings.defaultProject = name
        }
        persistSettings()
    }

    func removeProject(_ name: String) {
        settings.projects.removeAll { $0.name == name }
        if settings.defaultProject == name {
            settings.defaultProject = settings.projects.first?.name
        }
        persistSettings()
    }

    func setDefaultProject(_ name: String?) {
        settings.defaultProject = name
        persistSettings()
    }

    func openSettingsFile() {
        NSWorkspace.shared.open(Paths.settingsFile)
    }

    private func localizedError(_ error: Error) -> String {
        if let error = error as? SpaceServiceError {
            switch error {
            case .emptyBranchName:
                return localized("error.branch_empty")
            case .emptyBaseBranch:
                return localized("error.base_branch_empty")
            case .invalidPullRequest:
                return localized("error.invalid_pr")
            case .destinationExists(let path):
                return localized("error.destination_exists", path)
            }
        }

        if let error = error as? ShellError {
            switch error {
            case .toolNotFound(let tool):
                return localized("error.tool_not_found", tool)
            case .commandFailed(let command, let stderr):
                let detail = stderr.isEmpty ? "" : "\n\(stderr)"
                return localized("error.command_failed", command, detail)
            }
        }

        if let error = error as? EventSocketServer.SocketError {
            switch error {
            case .creationFailed:
                return localized("error.event_socket_creation")
            case .pathTooLong(let path):
                return localized("error.event_socket_path", path)
            case .bindFailed(let path):
                return localized("error.event_socket_bind", path)
            }
        }

        return error.localizedDescription
    }
}

/// Formats a stored RFC3339 timestamp for display; falls back to the raw string.
func formatCreatedAt(_ raw: String, locale: Locale) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime]
    guard let date = parser.date(from: raw) else { return raw }
    let out = DateFormatter()
    out.locale = locale
    out.dateStyle = .medium
    out.timeStyle = .short
    return out.string(from: date)
}
