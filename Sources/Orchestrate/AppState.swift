import AppKit
import Foundation
import OrchestrateCore
import SwiftUI

/// Observable app state: loads settings + tracked spaces and exposes the actions
/// wired to the UI. All blocking work (git, editors) runs off the main actor.
@MainActor
final class AppState: ObservableObject {
    @Published var settings = Settings()
    @Published var spaces: [TrackedSpace] = []
    @Published var agents: [AgentDefinition] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    /// Set by the menu bar to ask the window to present the create sheet.
    @Published var pendingNewSpace = false
    @Published var pendingSettings = false
    /// Asks the window to select a space (set when launching an agent).
    @Published var pendingSelectSpace: String?

    /// Installed by the app delegate; brings the main window to the front.
    var onShowWindow: (@MainActor () -> Void)?

    let sessionManager = SessionManager()

    func showMainWindow() {
        onShowWindow?()
    }

    private let spaceService = SpaceService()
    private let gitService = GitService()
    private let openService = OpenService()

    init() {
        reload()
        sessionManager.onError = { [weak self] message in
            self?.errorMessage = message
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
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Git queries (for the create form)

    func listBranches(project: Project) async -> [String] {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { (try? git.listBranches(repo: repo)) ?? [] }.value
    }

    func currentBranch(project: Project) async -> String? {
        let git = gitService
        let repo = URL(fileURLWithPath: project.path)
        return await Task.detached { git.currentBranch(repo: repo) }.value
    }

    // MARK: - Mutations

    /// Returns true on success. On failure sets `errorMessage`.
    func createSpace(project: Project, branchName: String, baseBranch: String) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        let service = spaceService
        do {
            _ = try await Task.detached {
                try service.create(
                    project: project, branchName: branchName, baseBranch: baseBranch)
            }.value
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Agents

    func launchAgent(_ agent: AgentDefinition, in space: TrackedSpace) {
        sessionManager.launch(agent: agent, in: space)
        pendingSelectSpace = space.name
        showMainWindow()
    }

    func persistAgents() {
        do {
            try AgentLibrary(agents: agents).save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Open actions

    func open(_ editor: Editor, _ space: TrackedSpace) {
        let service = openService
        let path = space.destination
        Task {
            do {
                try await Task.detached { try service.open(editor, at: path) }.value
            } catch {
                errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Settings management

    func persistSettings() {
        do {
            try settings.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addProject(path: URL) {
        let name = path.lastPathComponent
        guard !settings.projects.contains(where: { $0.name == name }) else {
            errorMessage = "Un projet nommé « \(name) » existe déjà."
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
}

/// Formats a stored RFC3339 timestamp for display; falls back to the raw string.
func formatCreatedAt(_ raw: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime]
    guard let date = parser.date(from: raw) else { return raw }
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .short
    return out.string(from: date)
}
