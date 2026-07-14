import ThreadBayCore
import SwiftUI

/// Creates a space from a Git branch, a GitHub pull request, or a plain folder.
struct NewSpaceView: View {
    private enum CreationMode: CaseIterable, Identifiable {
        case feature
        case existingBranch
        case pullRequest
        case folder

        var id: Self { self }

        var localizationKey: String {
            switch self {
            case .feature: return "new_space.mode.feature"
            case .existingBranch: return "new_space.mode.existing"
            case .pullRequest: return "new_space.mode.pr"
            case .folder: return "new_space.mode.folder"
            }
        }
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var mode: CreationMode = .feature
    @State private var branchName = ""
    @State private var displayName = ""
    @State private var isGitProject: Bool?
    @State private var selectedBaseID = ""
    @State private var selectedBranchID = ""
    @State private var searchText = ""
    @State private var branches: [GitBranch] = []
    @State private var loadingBranches = false
    @State private var selectedPullRequestNumber: UInt?
    @State private var pullRequestSearch = ""
    @State private var pullRequests: [PullRequestSummary] = []
    @State private var loadingPullRequests = false

    private var selectedProject: Project? {
        app.settings.projects.first { $0.name == projectName }
    }

    private var searchedPullRequestNumber: UInt? {
        let value = pullRequestSearch.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        guard let number = UInt(value), number > 0 else { return nil }
        return number
    }

    private var filteredBranches: [GitBranch] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return branches }
        return branches.filter { $0.referenceName.localizedCaseInsensitiveContains(query) }
    }

    private var filteredPullRequests: [PullRequestSummary] {
        let query = pullRequestSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return pullRequests }
        let numberQuery = query.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return pullRequests.filter {
            String($0.number).localizedCaseInsensitiveContains(numberQuery)
                || $0.title.localizedCaseInsensitiveContains(query)
                || $0.headRefName.localizedCaseInsensitiveContains(query)
        }
    }

    private var canCreate: Bool {
        guard selectedProject != nil, !app.isBusy else { return false }
        switch mode {
        case .feature:
            return !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && branch(id: selectedBaseID) != nil
        case .existingBranch:
            return branch(id: selectedBranchID) != nil
        case .pullRequest:
            return selectedPullRequestNumber != nil
        case .folder:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(app.localized("new_space.title")).font(.title2).bold()

            if app.settings.projects.isEmpty {
                Text(app.localized("new_space.no_projects"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 14) {
                    fieldRow(app.localized("new_space.project")) {
                        Picker("", selection: $projectName) {
                            ForEach(app.settings.projects) { Text($0.name).tag($0.name) }
                        }
                        .labelsHidden()
                    }

                    fieldRow(app.localized("new_space.display_name")) {
                        TextField(
                            "", text: $displayName,
                            prompt: Text(app.localized("new_space.display_name_placeholder")))
                            .labelsHidden()
                    }

                    if isGitProject == true {
                        fieldRow(app.localized("new_space.source")) {
                            Picker("", selection: $mode) {
                                ForEach(CreationMode.allCases.filter { $0 != .folder }) {
                                    Text(app.localized($0.localizationKey)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    } else if isGitProject == false {
                        fieldRow(app.localized("new_space.source")) {
                            Label(
                                app.localized("new_space.plain_folder"),
                                systemImage: "folder")
                                .foregroundStyle(.secondary)
                        }
                    }

                    modeFields
                }
            }

            HStack {
                if app.isBusy {
                    ProgressView().controlSize(.small)
                    Text(app.localized("new_space.creating")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(app.localized("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(app.localized("common.create")) { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .frame(width: 620)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .task { await setup() }
        .onChange(of: projectName) { _, _ in
            searchText = ""
            pullRequestSearch = ""
            pullRequests = []
            selectedPullRequestNumber = nil
            Task {
                await configureProject()
                if mode == .pullRequest { await loadPullRequests() }
            }
        }
        .onChange(of: mode) { _, _ in
            searchText = ""
            if mode == .pullRequest {
                pullRequestSearch = ""
                Task { await loadPullRequests() }
            } else if mode != .folder {
                selectFirstFilteredBranchIfNeeded()
            }
        }
        .onChange(of: searchText) { _, _ in
            selectFirstFilteredBranchIfNeeded()
        }
        .onChange(of: pullRequestSearch) { _, _ in
            selectFirstFilteredPullRequestIfNeeded()
        }
        .task(id: pullRequestSearch) {
            await resolveSearchedPullRequest()
        }
    }

    private func fieldRow<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(label)
                .frame(width: 132, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch mode {
        case .feature:
            fieldRow(app.localized("new_space.branch_name")) {
                TextField(
                    "", text: $branchName,
                    prompt: Text(app.localized("new_space.branch_placeholder")))
                .labelsHidden()
            }
            branchSelector(
                app.localized("new_space.base_branch"), selection: $selectedBaseID)
        case .existingBranch:
            branchSelector(app.localized("new_space.branch"), selection: $selectedBranchID)
        case .pullRequest:
            pullRequestSelector
        case .folder:
            EmptyView()
        }
    }

    private func branchSelector(_ title: String, selection: Binding<String>) -> some View {
        fieldRow(title, alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(app.localized("new_space.search"), text: $searchText)
                        .textFieldStyle(.plain)
                    if loadingBranches {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        Task { await loadBranches(refresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(loadingBranches)
                    .help(app.localized("new_space.reload"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        branchSection(
                            title: app.localized("new_space.local_branches"),
                            branches: filteredBranches.filter { $0.location == .local },
                            selection: selection)
                        branchSection(
                            title: app.localized("new_space.remote_branches"),
                            branches: filteredBranches.filter {
                                if case .remote = $0.location { return true }
                                return false
                            },
                            selection: selection)

                        if filteredBranches.isEmpty, !loadingBranches {
                            Text(app.localized("new_space.no_branches"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 172)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func branchSection(
        title: String,
        branches: [GitBranch],
        selection: Binding<String>
    ) -> some View {
        if !branches.isEmpty {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 3)

            ForEach(branches) { branch in
                Button {
                    selection.wrappedValue = branch.id
                } label: {
                    HStack(spacing: 8) {
                        if selection.wrappedValue == branch.id {
                            Image(systemName: "checkmark").frame(width: 12)
                        } else {
                            Color.clear.frame(width: 12, height: 12)
                        }
                        Text(branchDisplayName(branch))
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        selection.wrappedValue == branch.id
                            ? Color.accentColor.opacity(0.18) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func branchDisplayName(_ branch: GitBranch) -> String {
        switch branch.location {
        case .local:
            return app.localized("branch.local", branch.referenceName)
        case .remote:
            return app.localized("branch.remote", branch.referenceName)
        }
    }

    private var pullRequestSelector: some View {
        fieldRow(app.localized("new_space.mode.pr"), alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(app.localized("new_space.pr_search"), text: $pullRequestSearch)
                        .textFieldStyle(.plain)
                    if loadingPullRequests {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        Task { await loadPullRequests() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(loadingPullRequests)
                    .help(app.localized("new_space.pr_reload"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !filteredPullRequests.isEmpty {
                            Text(app.localized("new_space.pull_requests").uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 7)
                                .padding(.bottom, 3)

                            ForEach(filteredPullRequests) { pullRequest in
                                pullRequestRow(pullRequest)
                            }
                        } else if !loadingPullRequests {
                            Text(app.localized("new_space.no_pull_requests"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 190)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func pullRequestRow(_ pullRequest: PullRequestSummary) -> some View {
        Button {
            selectedPullRequestNumber = pullRequest.number
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if selectedPullRequestNumber == pullRequest.number {
                    Image(systemName: "checkmark").frame(width: 12)
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(pullRequest.number) · \(pullRequest.title)")
                        .lineLimit(2)
                    Label(pullRequest.headRefName, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedPullRequestNumber == pullRequest.number
                    ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func branch(id: String) -> GitBranch? {
        branches.first { $0.id == id }
    }

    private func selectFirstFilteredBranchIfNeeded() {
        guard mode != .pullRequest, mode != .folder else { return }
        let selectedID = mode == .feature ? selectedBaseID : selectedBranchID
        guard !filteredBranches.contains(where: { $0.id == selectedID }) else { return }
        let fallback = filteredBranches.first?.id ?? ""
        if mode == .feature {
            selectedBaseID = fallback
        } else {
            selectedBranchID = fallback
        }
    }

    private func selectFirstFilteredPullRequestIfNeeded() {
        guard mode == .pullRequest else { return }
        guard filteredPullRequests.contains(where: {
            $0.number == selectedPullRequestNumber
        }) else {
            selectedPullRequestNumber = filteredPullRequests.first?.number
            return
        }
    }

    private func setup() async {
        if projectName.isEmpty {
            projectName = app.settings.defaultProject ?? app.settings.projects.first?.name ?? ""
        }
        await configureProject()
    }

    private func configureProject() async {
        guard let project = selectedProject else {
            isGitProject = nil
            branches = []
            return
        }
        let isGit = await app.isGitProject(project)
        guard project.name == projectName else { return }
        isGitProject = isGit
        if isGit {
            if mode == .folder { mode = .feature }
            await loadBranches()
        } else {
            mode = .folder
            branches = []
            selectedBaseID = ""
            selectedBranchID = ""
        }
    }

    private func loadBranches(refresh: Bool = false) async {
        guard let project = selectedProject else {
            branches = []
            selectedBaseID = ""
            selectedBranchID = ""
            return
        }
        guard isGitProject == true else { return }

        loadingBranches = true
        defer { loadingBranches = false }
        let listed: [GitBranch]?
        if refresh {
            listed = await app.refreshBranches(project: project)
        } else {
            listed = await app.listBranches(project: project)
        }
        let current = await app.currentBranch(project: project)
        guard project.name == projectName, let listed else { return }

        branches = listed
        let currentLocal = listed.first { $0.name == current && $0.location == .local }
        let fallback = currentLocal ?? listed.first
        if branch(id: selectedBaseID) == nil {
            selectedBaseID = fallback?.id ?? ""
        }
        if branch(id: selectedBranchID) == nil {
            selectedBranchID = fallback?.id ?? ""
        }
        selectFirstFilteredBranchIfNeeded()
    }

    private func loadPullRequests() async {
        guard let project = selectedProject else {
            pullRequests = []
            selectedPullRequestNumber = nil
            return
        }

        loadingPullRequests = true
        defer { loadingPullRequests = false }
        let resolvedPullRequest = searchedPullRequestNumber.flatMap { number in
            pullRequests.first { $0.number == number }
        }
        let listed = await app.listPullRequests(project: project)
        guard project.name == projectName, let listed else { return }

        pullRequests = listed
        if let resolvedPullRequest,
            !pullRequests.contains(where: { $0.number == resolvedPullRequest.number })
        {
            pullRequests.insert(resolvedPullRequest, at: 0)
        }
        selectFirstFilteredPullRequestIfNeeded()
    }

    private func resolveSearchedPullRequest() async {
        guard mode == .pullRequest,
            let project = selectedProject,
            let number = searchedPullRequestNumber,
            !pullRequests.contains(where: { $0.number == number })
        else { return }

        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        guard !Task.isCancelled,
            mode == .pullRequest,
            project.name == projectName,
            searchedPullRequestNumber == number,
            let pullRequest = await app.pullRequest(project: project, number: number)
        else { return }

        pullRequests.insert(pullRequest, at: 0)
        selectedPullRequestNumber = pullRequest.number
    }

    private func create() async {
        guard let project = selectedProject else { return }

        let creation: SpaceCreation
        switch mode {
        case .feature:
            guard let base = branch(id: selectedBaseID) else { return }
            creation = .feature(branchName: branchName, base: base)
        case .existingBranch:
            guard let branch = branch(id: selectedBranchID) else { return }
            creation = .existingBranch(branch)
        case .pullRequest:
            guard let number = selectedPullRequestNumber else { return }
            creation = .pullRequest(number)
        case .folder:
            creation = .folder(name: project.name)
        }

        if await app.createSpace(
            project: project, creation: creation, displayName: displayName)
        {
            dismiss()
        }
    }
}
