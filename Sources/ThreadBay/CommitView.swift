import ThreadBayCore
import SwiftUI

struct CommitView: View {
    enum Mode {
        case manual
        case automatic(name: String, provider: CommitMessageProvider)
    }

    private enum PostAction: String, CaseIterable, Identifiable {
        case commit
        case push
        case merge
        case mergeAndPush

        var id: Self { self }
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let space: TrackedSpace
    let mode: Mode

    @State private var message = ""
    @State private var files: [String] = []
    @State private var branches: [GitBranch] = []
    @State private var targetID = ""
    @State private var postAction = PostAction.commit
    @State private var loading = true
    @State private var generating = false

    private var selectedTarget: GitBranch? {
        mergeTargets.first { $0.id == targetID }
    }

    private var mergeTargets: [GitBranch] {
        let current = app.currentBranch(for: space)
        return branches.filter { $0.name != current }
    }

    private var needsMergeTarget: Bool {
        postAction == .merge || postAction == .mergeAndPush
    }

    private var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !files.isEmpty
            && (!needsMergeTarget || selectedTarget != nil)
            && !app.isBusy
            && !generating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            Text(app.localized("git.commit_all_help"))
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox(app.localized("git.changed_files", files.count)) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 90)
                } else if files.isEmpty {
                    Text(app.localized("git.no_changes"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    List(files, id: \.self) { Text($0).font(.body.monospaced()) }
                        .frame(height: 130)
                }
            }

            HStack {
                Text(app.localized("git.commit_message")).font(.headline)
                Spacer()
                if case .automatic = mode {
                    Button(app.localized("git.regenerate")) {
                        Task { await generateMessage() }
                    }
                    .disabled(generating || files.isEmpty)
                }
            }

            ZStack {
                TextEditor(text: $message)
                    .font(.body.monospaced())
                    .frame(height: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    }
                if generating {
                    ProgressView(app.localized("git.generating_message"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Picker(app.localized("git.after_commit"), selection: $postAction) {
                ForEach(PostAction.allCases) { action in
                    Text(postActionName(action)).tag(action)
                }
            }

            if needsMergeTarget {
                Picker(app.localized("git.merge_target"), selection: $targetID) {
                    ForEach(mergeTargets) { branch in
                        Text(branch.referenceName).tag(branch.id)
                    }
                }
            }

            HStack {
                Spacer()
                Button(app.localized("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(app.localized("git.create_commit")) {
                    Task { await commit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            }
        }
        .padding(22)
        .frame(width: 620)
        .task { await load() }
    }

    private var title: String {
        switch mode {
        case .manual:
            return app.localized("git.commit_title", space.displayTitle)
        case .automatic(let name, _):
            return app.localized("git.automatic_commit_title", name, space.displayTitle)
        }
    }

    private func postActionName(_ action: PostAction) -> String {
        switch action {
        case .commit: return app.localized("git.after_commit.none")
        case .push: return app.localized("git.after_commit.push")
        case .merge: return app.localized("git.after_commit.merge")
        case .mergeAndPush: return app.localized("git.after_commit.merge_push")
        }
    }

    private func load() async {
        async let loadedFiles = app.changedFiles(in: space)
        async let loadedBranches = app.listBranches(space: space)
        files = await loadedFiles ?? []
        branches = await loadedBranches ?? []
        let base = app.gitState(for: space)?.baseBranch
        targetID = mergeTargets.first(where: { $0 == base })?.id
            ?? mergeTargets.first(where: { $0.name == base?.name })?.id
            ?? mergeTargets.first?.id
            ?? ""
        loading = false
        if case .automatic = mode, !files.isEmpty {
            await generateMessage()
        }
    }

    private func generateMessage() async {
        guard case .automatic(_, let provider) = mode else { return }
        generating = true
        defer { generating = false }
        if let generated = await app.generateCommitMessage(with: provider, in: space) {
            message = generated
        }
    }

    private func commit() async {
        let target = needsMergeTarget ? selectedTarget : nil
        let success = await app.commit(
            in: space,
            message: message,
            expectedFiles: files,
            push: postAction == .push,
            mergeInto: target,
            pushMerge: postAction == .mergeAndPush)
        if success { dismiss() }
    }
}
