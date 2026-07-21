import AppKit
import Foundation
import ThreadBayCore
import SwiftUI

/// What to do right after a successful commit.
enum CommitFollowUp {
    case none
    case push(forceWithLease: Bool)
    case merge(into: GitBranch, push: Bool)
}

/// Observable app state: loads settings + tracked spaces and exposes the actions
/// wired to the UI. All blocking work (git, editors) runs off the main actor.
@MainActor
final class AppState: ObservableObject {
    private static let terminalThemeKey = "terminalTheme"
    private static let appLanguageKey = "appLanguage"

    @Published var settings = Settings()
    @Published var spaces: [TrackedSpace] = []
    @Published private(set) var gitStates: [String: GitRepositoryState] = [:]
    @Published var agents: [AgentDefinition] = []
    @Published var commitGenerators: [CommitGeneratorDefinition] = []
    @Published private(set) var shortcuts: AppShortcutSettings
    @Published private(set) var terminalTheme: TerminalTheme
    @Published private(set) var terminalFont: TerminalFontSettings
    @Published private(set) var appLanguage: AppLanguage
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var successMessage: String?
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
    private let commitMessageService = CommitMessageService()
    private let githubService = GitHubService()
    private let openService = OpenService()
    private var gitHeadMonitors: [String: GitHeadMonitor] = [:]

    init() {
        shortcuts = AppShortcutSettings.load()
        terminalFont = TerminalFontSettings.load()
        appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? ""
        ) ?? .system
        terminalTheme = TerminalTheme(
            rawValue: UserDefaults.standard.string(forKey: Self.terminalThemeKey) ?? ""
        ) ?? .system
        reload()
        sessionManager.setLanguage(appLanguage)
        sessionManager.setTerminalTheme(terminalTheme)
        sessionManager.setTerminalFont(terminalFont)
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
            .map {
                ProjectGroup(
                    id: $0.key,
                    spaces: $0.value.sorted { $0.displayTitle < $1.displayTitle })
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Loading

    func reload() {
        do {
            settings = try Settings.load()
            spaces = try SpaceStore.load().spaces
            let library = try AgentLibrary.load()
            agents = library.agents
            commitGenerators = library.commitGenerators
            let currentSpaces = spaces
            synchronizeGitHeadMonitors(with: currentSpaces)
            Task { await refreshGitStates(for: currentSpaces) }
        } catch {
            errorMessage = localizedError(error)
        }
    }

    // MARK: - Git queries (for the create form)

    func isGitProject(_ project: Project) async -> Bool {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { git.isRepository(repo: repo) }.value
    }

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
            return await localBranchesFallback(repo: repo, fetchError: error)
        }
    }

    /// A failed fetch (network down, concurrent git holding a ref lock…)
    /// degrades to the locally known refs with a warning instead of blocking
    /// branch selection.
    private func localBranchesFallback(repo: URL, fetchError: Error) async -> [GitBranch]? {
        let git = gitService
        let local = await Task.detached { try? git.listBranches(repo: repo) }.value
        guard let branches = local else {
            errorMessage = localizedError(fetchError)
            return nil
        }
        errorMessage = localized("git.fetch_failed_stale_branches", localizedError(fetchError))
        return branches
    }

    func currentBranch(project: Project) async -> String? {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { git.currentBranch(repo: repo) }.value
    }

    /// Moves the pending error into the caller's hands. Sheets use this to
    /// show the error inline, where the window-level alert cannot appear.
    func consumeErrorMessage() -> String? {
        defer { errorMessage = nil }
        return errorMessage
    }

    func gitState(for space: TrackedSpace) -> GitRepositoryState? {
        gitStates[space.name]
    }

    func currentBranch(for space: TrackedSpace) -> String? {
        gitState(for: space)?.currentBranch
    }

    func refreshGitState(for space: TrackedSpace) async {
        guard space.supportsGitActions else {
            gitStates[space.name] = nil
            return
        }
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        let state = await Task.detached { try? git.repositoryState(repo: repo) }.value
        guard spaces.contains(where: { $0.name == space.name }) else { return }
        gitStates[space.name] = state
    }

    func refreshGitStates() async {
        await refreshGitStates(for: spaces)
    }

    func listBranches(space: TrackedSpace, refresh: Bool = false) async -> [GitBranch]? {
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        do {
            return try await Task.detached {
                refresh
                    ? try git.refreshBranches(repo: repo)
                    : try git.listBranches(repo: repo)
            }.value
        } catch {
            guard refresh else {
                errorMessage = localizedError(error)
                return nil
            }
            return await localBranchesFallback(repo: repo, fetchError: error)
        }
    }

    func switchBranch(_ branch: GitBranch, in space: TrackedSpace) async -> Bool {
        guard !sessionManager.isWorking(space) else {
            errorMessage = localized("error.agent_working_git_action")
            return false
        }
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        do {
            let result = try await Task.detached {
                try git.switchBranch(branch, repo: repo)
            }.value
            await refreshGitState(for: space)
            if case .switchedWithWarning(let detail) = result {
                noticeMessage = localized("git.switch_completed_with_warning", branch.name, detail)
            }
            return true
        } catch {
            await refreshGitState(for: space)
            errorMessage = localizedError(error)
            return false
        }
    }

    func changedFiles(in space: TrackedSpace) async -> [String]? {
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        return await performReporting { try git.changedFiles(repo: repo) }
    }

    func generateCommitMessage(
        with provider: CommitMessageProvider,
        in space: TrackedSpace
    ) async -> String? {
        guard !sessionManager.isWorking(space) else {
            errorMessage = localized("error.agent_working_git_action")
            return nil
        }
        let service = commitMessageService
        let repo = URL(fileURLWithPath: space.destination)
        return await performReporting {
            try service.generate(provider: provider, repo: repo)
        }
    }

    func commit(
        in space: TrackedSpace,
        message: String,
        expectedFiles: [String],
        followUp: CommitFollowUp
    ) async -> Bool {
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        return await performGitAction(in: space) {
            try git.commitAll(
                message: message, expectedFiles: expectedFiles, repo: repo)
            switch followUp {
            case .none:
                break
            case .push(let forceWithLease):
                try git.pushCurrentBranch(forceWithLease: forceWithLease, repo: repo)
            case .merge(let target, let push):
                try git.mergeCurrentBranch(into: target, push: push, repo: repo)
            }
        } successMessage: { current in
            switch followUp {
            case .none:
                return localized("git.success.commit", current)
            case .push(forceWithLease: false):
                return localized("git.success.push", current)
            case .push(forceWithLease: true):
                return localized("git.success.force_push", current)
            case .merge(let target, push: false):
                return localized("git.success.merge", target.name, current)
            case .merge(let target, push: true):
                return localized("git.success.merge_push", target.name, current)
            }
        }
    }

    /// Pushes the current branch without committing anything first.
    func push(in space: TrackedSpace, forceWithLease: Bool) async -> Bool {
        let git = gitService
        let repo = URL(fileURLWithPath: space.destination)
        return await performGitAction(in: space) {
            try git.pushCurrentBranch(forceWithLease: forceWithLease, repo: repo)
        } successMessage: { current in
            localized(forceWithLease ? "git.success.pushed_force" : "git.success.pushed", current)
        }
    }

    /// Runs `work` off the main actor and reports a thrown error via
    /// `errorMessage`. Returns nil on failure.
    @discardableResult
    private func performReporting<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async -> T? {
        do {
            return try await Task.detached(operation: work).value
        } catch {
            errorMessage = localizedError(error)
            return nil
        }
    }

    /// Shared scaffolding of the user-triggered git actions: refuses to run
    /// while an agent is working, flags the app busy, runs `action` off the
    /// main actor, refreshes the git state, and reports the outcome.
    /// `successMessage` receives the current branch label.
    private func performGitAction(
        in space: TrackedSpace,
        action: @escaping @Sendable () throws -> Void,
        successMessage: (String) -> String
    ) async -> Bool {
        guard !sessionManager.isWorking(space) else {
            errorMessage = localized("error.agent_working_git_action")
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached(operation: action).value
            await refreshGitState(for: space)
            self.successMessage = successMessage(branchLabel(for: space))
            return true
        } catch {
            await refreshGitState(for: space)
            errorMessage = localizedError(error)
            return false
        }
    }

    /// The current branch as shown in user-facing messages.
    func branchLabel(for space: TrackedSpace) -> String {
        currentBranch(for: space) ?? localized("git.unknown_branch")
    }

    private func refreshGitStates(for spaces: [TrackedSpace]) async {
        let git = gitService
        let states = await withTaskGroup(
            of: (String, GitRepositoryState?).self,
            returning: [String: GitRepositoryState].self
        ) { group in
            for space in spaces where space.supportsGitActions {
                group.addTask {
                    let repo = URL(fileURLWithPath: space.destination)
                    return (space.name, try? git.repositoryState(repo: repo))
                }
            }
            var loaded: [String: GitRepositoryState] = [:]
            for await (name, state) in group {
                if let state { loaded[name] = state }
            }
            return loaded
        }
        guard self.spaces.map(\.name) == spaces.map(\.name) else { return }
        gitStates = states
    }

    /// Keeps one event-driven HEAD watcher per Git space. Only the branch is
    /// refreshed on an external checkout, so observing HEAD cannot cause a
    /// feedback loop through `git status` updating the index.
    private func synchronizeGitHeadMonitors(with spaces: [TrackedSpace]) {
        let names = Set(spaces.lazy.filter(\.supportsGitActions).map(\.name))
        let removedNames = gitHeadMonitors.keys.filter { !names.contains($0) }
        for name in removedNames {
            gitHeadMonitors.removeValue(forKey: name)?.stop()
        }

        for space in spaces where space.supportsGitActions && gitHeadMonitors[space.name] == nil {
            let repository = URL(fileURLWithPath: space.destination)
            let name = space.name
            let monitor = GitHeadMonitor(repository: repository) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refreshCurrentBranch(forSpaceNamed: name)
                }
            }
            if monitor.start() {
                gitHeadMonitors[name] = monitor
            }
        }
    }

    private func refreshCurrentBranch(forSpaceNamed name: String) async {
        guard let space = spaces.first(where: { $0.name == name }),
            space.supportsGitActions
        else { return }

        let git = gitService
        let repository = URL(fileURLWithPath: space.destination)
        let branch = await Task.detached { git.currentBranch(repo: repository) }.value
        guard spaces.contains(where: { $0.name == name }) else { return }

        let previous = gitStates[name]
        gitStates[name] = GitRepositoryState(
            currentBranch: branch,
            baseBranch: previous?.baseBranch,
            hasChanges: previous?.hasChanges ?? false)
    }

    // MARK: - GitHub queries (for the pull-request selector)

    func listPullRequests(project: Project) async -> [PullRequestSummary]? {
        let github = githubService
        let repo = URL(fileURLWithPath: project.path)
        return await performReporting {
            try github.listOpenPullRequests(repo: repo)
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
    func createSpace(
        project: Project, creation: SpaceCreation, displayName: String? = nil
    ) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        let service = spaceService
        let created = await performReporting {
            try service.create(
                project: project, creation: creation, displayName: displayName)
        }
        guard created != nil else { return false }
        reload()
        return true
    }

    /// Creates a tracked terminal space (home directory, no copy or clone) and
    /// opens a shell session in it right away.
    func createTerminalSpace(displayName: String? = nil) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        let service = spaceService
        guard let space = await performReporting({
            try service.createTerminal(displayName: displayName)
        }) else { return false }
        spaces.append(space)
        if let shell = agents.first(where: { $0.kind == .shell }) {
            launchAgent(shell, in: space)
        } else {
            pendingSelectSpace = space.name
        }
        return true
    }

    /// Body of the delete-confirmation dialogs: a terminal space is only
    /// untracked, anything else loses its folder (and its running agents).
    func deleteConfirmationMessage(for space: TrackedSpace) -> String {
        guard !space.isTerminal else { return localized("main.delete_terminal") }
        let running = sessionManager.runningCount(for: space)
        if running > 0 {
            return localized("main.delete_folder_agents", space.destination, running)
        }
        return localized("main.delete_folder", space.destination)
    }

    func delete(_ space: TrackedSpace) {
        // Agents must not outlive the folder they run in.
        sessionManager.closeSessions(for: space)
        let service = spaceService
        Task {
            if await performReporting({ try service.delete(space) }) != nil {
                reload()
            }
        }
    }

    func rename(_ space: TrackedSpace, displayName: String) {
        do {
            var store = try SpaceStore.load()
            try store.rename(named: space.name, displayName: displayName)
            reload()
            if let updated = spaces.first(where: { $0.name == space.name }) {
                sessionManager.updateSpace(updated)
            }
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func deleteBranch(_ branch: GitBranch, from project: Project) async -> Bool {
        guard case .local = branch.location else { return false }
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await performReporting {
            try git.deleteLocalBranch(named: branch.name, repo: repo)
        } != nil
    }

    // MARK: - Agents

    func launchAgent(_ agent: AgentDefinition, in space: TrackedSpace) {
        Task {
            var branch: String?
            if space.supportsGitActions {
                branch = currentBranch(for: space)
                if branch == nil {
                    // Resolving the branch spawns git (and possibly a login
                    // shell); keep that off the main actor.
                    let git = gitService
                    let repo = URL(fileURLWithPath: space.destination)
                    branch = await Task.detached { git.currentBranch(repo: repo) }.value
                }
            }
            sessionManager.launch(
                agent: agent, in: space, currentBranch: branch)
            pendingSelectSpace = space.name
            showMainWindow()
        }
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
            try AgentLibrary(
                agents: agents, commitGenerators: commitGenerators).save()
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

    func setTerminalFont(_ font: TerminalFontSettings) {
        terminalFont = font
        font.save()
        sessionManager.setTerminalFont(font)
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
        Task { await performReporting { try service.open(editor, at: path) } }
    }

    func reveal(_ space: TrackedSpace) {
        let service = openService
        let path = space.destination
        Task { await performReporting { try service.revealInFinder(path) } }
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
            case .emptySpaceName:
                return localized("error.space_name_empty")
            case .invalidPullRequest:
                return localized("error.invalid_pr")
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

        if let error = error as? GitHubServiceError {
            switch error {
            case .noRemote:
                return localized("error.no_remote")
            }
        }

        if let error = error as? GitActionError {
            switch error {
            case .emptyCommitMessage:
                return localized("error.commit_message_empty")
            case .noChanges:
                return localized("error.no_changes")
            case .uncommittedChanges:
                return localized("error.uncommitted_changes")
            case .noCurrentBranch:
                return localized("error.no_current_branch")
            case .noPushRemote:
                return localized("error.no_push_remote")
            case .currentBranchIsMergeTarget:
                return localized("error.merge_same_branch")
            case .changesChanged:
                return localized("error.changes_changed")
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

/// Formatter construction is expensive and this runs in list-row bodies on
/// every publish, so both formatters are cached (the display one per locale).
@MainActor
private let createdAtParser: ISO8601DateFormatter = {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime]
    return parser
}()

@MainActor
private var createdAtFormatters: [Locale: DateFormatter] = [:]

/// Formats a stored RFC3339 timestamp for display; falls back to the raw string.
@MainActor
func formatCreatedAt(_ raw: String, locale: Locale) -> String {
    guard let date = createdAtParser.date(from: raw) else { return raw }
    if let formatter = createdAtFormatters[locale] {
        return formatter.string(from: date)
    }
    let out = DateFormatter()
    out.locale = locale
    out.dateStyle = .medium
    out.timeStyle = .short
    createdAtFormatters[locale] = out
    return out.string(from: date)
}
