import ThreadBayCore
import SwiftUI

/// Central place for user-facing space names and safe local branch cleanup.
struct SpaceManagementView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var branches: [GitBranch] = []
    @State private var currentBranch: String?
    @State private var isGitProject = false
    @State private var loadingBranches = false
    @State private var renameSpace: TrackedSpace?
    @State private var renameText = ""
    @State private var spaceToDelete: TrackedSpace?
    @State private var branchToDelete: GitBranch?

    private var selectedProject: Project? {
        app.settings.projects.first { $0.name == projectName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.localized("management.title")).font(.title2).bold()

            TabView {
                spacesList
                    .tabItem { Label(app.localized("management.spaces"), systemImage: "square.stack.3d.up") }
                branchesList
                    .tabItem { Label(app.localized("management.branches"), systemImage: "arrow.triangle.branch") }
            }

            HStack {
                Spacer()
                Button(app.localized("common.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 520)
        .task { await setupBranches() }
        .onChange(of: projectName) { _, _ in Task { await loadBranches() } }
        .renameSpaceAlert(space: $renameSpace, text: $renameText)
        .confirmationDialog(
            app.localized("management.delete_branch_title", branchToDelete?.name ?? ""),
            isPresented: Binding(presence: $branchToDelete),
            titleVisibility: .visible
        ) {
            Button(app.localized("common.delete"), role: .destructive) {
                guard let project = selectedProject, let branch = branchToDelete else { return }
                branchToDelete = nil
                Task {
                    if await app.deleteBranch(branch, from: project) { await loadBranches() }
                }
            }
            Button(app.localized("common.cancel"), role: .cancel) { branchToDelete = nil }
        } message: {
            Text(app.localized("management.delete_branch_help"))
        }
        .confirmDeleteSpace($spaceToDelete)
    }

    private var spacesList: some View {
        List {
            if app.spaces.isEmpty {
                Text(app.localized("main.no_spaces")).foregroundStyle(.secondary)
            }
            ForEach(app.groups) { group in
                Section(group.id) {
                    ForEach(group.spaces) { space in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.displayTitle)
                                Text(space.destination)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                renameSpace = space
                                renameText = space.displayTitle
                            } label: {
                                Label(app.localized("management.rename"), systemImage: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            Button(role: .destructive) { spaceToDelete = space } label: {
                                Label(app.localized("common.delete"), systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
    }

    private var branchesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(app.localized("new_space.project"), selection: $projectName) {
                    ForEach(app.settings.projects) { project in
                        Text(project.name).tag(project.name)
                    }
                }
                Button { Task { await loadBranches(refresh: true) } } label: {
                    Label(app.localized("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(loadingBranches || !isGitProject)
            }

            if loadingBranches {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isGitProject {
                ContentUnavailableView(
                    app.localized("management.not_git"),
                    systemImage: "folder",
                    description: Text(app.localized("management.not_git_help")))
            } else {
                List {
                    branchSection(
                        app.localized("new_space.local_branches"),
                        branches.filter(\.isLocal))
                    branchSection(
                        app.localized("new_space.remote_branches"),
                        branches.filter(\.isRemote))
                }
            }
        }
        .padding(12)
    }

    private func branchSection(_ title: String, _ listed: [GitBranch]) -> some View {
        Section(title) {
            ForEach(listed) { branch in
                HStack {
                    Text(branch.referenceName)
                    if branch.location == .local, branch.name == currentBranch {
                        Text(app.localized("management.current_branch"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if branch.location == .local {
                        Button(role: .destructive) { branchToDelete = branch } label: {
                            Label(app.localized("common.delete"), systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .disabled(branch.name == currentBranch)
                    }
                }
            }
        }
    }

    private func setupBranches() async {
        projectName = app.settings.defaultProject ?? app.settings.projects.first?.name ?? ""
        await loadBranches()
    }

    private func loadBranches(refresh: Bool = false) async {
        guard let project = selectedProject else {
            branches = []
            isGitProject = false
            return
        }
        loadingBranches = true
        defer { loadingBranches = false }
        let gitProject = await app.isGitProject(project)
        guard project.name == projectName else { return }
        isGitProject = gitProject
        guard gitProject else {
            branches = []
            currentBranch = nil
            return
        }
        async let currentTask = app.currentBranch(project: project)
        let listed = refresh
            ? await app.refreshBranches(project: project)
            : await app.listBranches(project: project)
        let current = await currentTask
        guard project.name == projectName else { return }
        branches = listed ?? []
        currentBranch = current
    }
}
