import ThreadBayCore
import SwiftUI

struct BranchSwitcherView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let space: TrackedSpace

    @State private var branches: [GitBranch] = []
    @State private var query = ""
    @State private var loading = false

    private var filteredBranches: [GitBranch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return branches }
        return branches.filter {
            $0.referenceName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.localized("git.switch_branch_title", space.displayTitle))
                .font(.title2.bold())

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(app.localized("git.search_branches"), text: $query)
                    .textFieldStyle(.plain)
                if loading { ProgressView().controlSize(.small) }
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(loading)
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            List {
                branchSection(
                    app.localized("new_space.local_branches"),
                    branches: filteredBranches.filter(\.isLocal))
                branchSection(
                    app.localized("new_space.remote_branches"),
                    branches: filteredBranches.filter(\.isRemote))
            }
            .overlay {
                if filteredBranches.isEmpty, !loading {
                    ContentUnavailableView.search(text: query)
                }
            }

            HStack {
                if let branch = app.currentBranch(for: space) {
                    Text(app.localized("git.current_branch", branch))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(app.localized("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .task { await load() }
    }

    @ViewBuilder
    private func branchSection(_ title: String, branches: [GitBranch]) -> some View {
        if !branches.isEmpty {
            Section(title) {
                ForEach(branches) { branch in
                    Button {
                        Task {
                            if await app.switchBranch(branch, in: space) { dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(branch.referenceName)
                            Spacer()
                            if branch.name == app.currentBranch(for: space) {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(branch.name == app.currentBranch(for: space))
                }
            }
        }
    }

    private func load(refresh: Bool = false) async {
        loading = true
        defer { loading = false }
        if let listed = await app.listBranches(space: space, refresh: refresh) {
            branches = listed
        }
    }
}
