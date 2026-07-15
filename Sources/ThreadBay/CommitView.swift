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
        case forcePush
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
    @State private var errorText: String?

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

            if let errorText {
                ErrorBanner(text: errorText)
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
        case .forcePush: return app.localized("git.after_commit.force_push")
        case .merge: return app.localized("git.after_commit.merge")
        case .mergeAndPush: return app.localized("git.after_commit.merge_push")
        }
    }

    private func load() async {
        async let loadedFiles = app.changedFiles(in: space)
        async let loadedBranches = app.listBranches(space: space)
        files = await loadedFiles ?? []
        branches = await loadedBranches ?? []
        errorText = app.consumeErrorMessage()
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
        } else {
            errorText = app.consumeErrorMessage()
        }
    }

    private var followUp: CommitFollowUp {
        switch postAction {
        case .commit: return .none
        case .push: return .push(forceWithLease: false)
        case .forcePush: return .push(forceWithLease: true)
        case .merge, .mergeAndPush:
            guard let target = selectedTarget else { return .none }
            return .merge(into: target, push: postAction == .mergeAndPush)
        }
    }

    private func commit() async {
        errorText = nil
        let success = await app.commit(
            in: space,
            message: message,
            expectedFiles: files,
            followUp: followUp)
        if success {
            dismiss()
        } else {
            errorText = app.consumeErrorMessage()
        }
    }
}
