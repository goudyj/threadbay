import AppKit
import ThreadBayCore
import SwiftUI

private struct CommitRequest: Identifiable {
    let id = UUID()
    let space: TrackedSpace
    let mode: CommitView.Mode
}

/// Main window: spaces sidebar (with agent badges) + detail area showing the
/// selected space and its embedded agent terminals. Also hosts the create and
/// settings sheets, and drives the Dock/activation policy while visible.
struct MainWindow: View {
    @EnvironmentObject var app: AppState

    @State private var showNew = false
    @State private var showSettings = false
    @State private var showManagement = false
    @State private var renameSpace: TrackedSpace?
    @State private var renameText = ""
    @State private var branchSwitchSpace: TrackedSpace?
    @State private var commitRequest: CommitRequest?

    private var selectedSpace: TrackedSpace? {
        app.spaces.first { $0.name == app.selectedSpaceName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                List(selection: $app.selectedSpaceName) {
                    Label(app.localized("main.all_spaces"), systemImage: "square.stack.3d.up")
                        .tag("")
                    ForEach(app.groups) { group in
                        Section(group.id) {
                            ForEach(group.spaces) { space in
                                SidebarSpaceRow(
                                    space: space,
                                    manager: app.sessionManager,
                                    onCommit: { presentCommit(for: space) },
                                    onAutomaticCommit: {
                                        presentAutomaticCommit($0, name: $1, for: space)
                                    },
                                    onSwitchBranch: { branchSwitchSpace = space })
                                    .tag(space.name)
                                    .contextMenu {
                                        Button {
                                            renameSpace = space
                                            renameText = space.displayTitle
                                        } label: {
                                            Label(
                                                app.localized("management.rename"),
                                                systemImage: "pencil")
                                        }
                                        if space.taskType != "folder" {
                                            Divider()
                                            Button {
                                                presentCommit(for: space)
                                            } label: {
                                                Label(
                                                    app.localized("git.create_commit"),
                                                    systemImage: "checkmark.circle")
                                            }
                                            Menu(app.localized("git.automatic_commit")) {
                                                Button("Claude") {
                                                    presentAutomaticCommit(
                                                        .claude, name: "Claude", for: space)
                                                }
                                                Button("Codex") {
                                                    presentAutomaticCommit(
                                                        .codex, name: "Codex", for: space)
                                                }
                                                if !app.commitGenerators.isEmpty {
                                                    Divider()
                                                    ForEach(app.commitGenerators) { generator in
                                                        Button(generator.name) {
                                                            presentAutomaticCommit(
                                                                .custom(command: generator.command),
                                                                name: generator.name,
                                                                for: space)
                                                        }
                                                        .disabled(generator.command
                                                            .trimmingCharacters(
                                                                in: .whitespacesAndNewlines).isEmpty)
                                                    }
                                                }
                                            }
                                            Button {
                                                branchSwitchSpace = space
                                            } label: {
                                                Label(
                                                    app.localized("git.switch_branch"),
                                                    systemImage: "arrow.triangle.branch")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(minWidth: 200)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .sheet(isPresented: $showNew) { NewSpaceView().environmentObject(app) }
        .sheet(isPresented: $showManagement) { SpaceManagementView().environmentObject(app) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(app) }
        .sheet(item: $branchSwitchSpace) { space in
            BranchSwitcherView(space: space).environmentObject(app)
        }
        .sheet(item: $commitRequest) { request in
            CommitView(space: request.space, mode: request.mode).environmentObject(app)
        }
        .onAppear {
            app.reload()
            applyPending()
        }
        .onChange(of: app.pendingNewSpace) { _, _ in applyPending() }
        .onChange(of: app.pendingSettings) { _, _ in applyPending() }
        .onChange(of: app.pendingSelectSpace) { _, _ in applyPending() }
        .onChange(of: app.selectedSpaceName) { _, name in
            guard let space = app.spaces.first(where: { $0.name == name }) else { return }
            Task { await app.refreshGitState(for: space) }
        }
        .alert(app.localized("main.error"), isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .alert(app.localized("main.warning"), isPresented: noticePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.noticeMessage ?? "")
        }
        .alert(
            app.localized("management.rename_title", renameSpace?.displayTitle ?? ""),
            isPresented: renamePresented
        ) {
            TextField(app.localized("management.display_name"), text: $renameText)
            Button(app.localized("common.cancel"), role: .cancel) { renameSpace = nil }
            Button(app.localized("management.rename")) {
                if let space = renameSpace { app.rename(space, displayName: renameText) }
                renameSpace = nil
            }
        } message: {
            Text(app.localized("management.rename_help"))
        }
        .confirmationDialog(
            closeSessionTitle,
            isPresented: closeSessionPresented,
            titleVisibility: .visible
        ) {
            Button(app.localized("terminal.close_confirm"), role: .destructive) {
                app.confirmCloseSession()
            }
            Button(app.localized("common.cancel"), role: .cancel) {
                app.cancelCloseSession()
            }
        } message: {
            Text(app.localized("terminal.close_message"))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { showNew = true } label: {
                Label(app.localized("main.new_space"), systemImage: "plus")
            }
            .disabled(app.settings.projects.isEmpty)
            Spacer()
            Button { app.reload() } label: {
                Label(app.localized("common.refresh"), systemImage: "arrow.clockwise")
            }
            Button { showManagement = true } label: {
                Label(app.localized("management.title"), systemImage: "slider.horizontal.3")
            }
            Button { showSettings = true } label: {
                Label(app.localized("common.settings"), systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func applyPending() {
        if app.pendingNewSpace {
            showNew = true
            app.pendingNewSpace = false
        }
        if app.pendingSettings {
            showSettings = true
            app.pendingSettings = false
        }
        if let name = app.pendingSelectSpace {
            app.selectedSpaceName = name
            app.pendingSelectSpace = nil
        }
    }

    private func presentCommit(for space: TrackedSpace) {
        commitRequest = CommitRequest(space: space, mode: .manual)
    }

    private func presentAutomaticCommit(
        _ provider: CommitMessageProvider,
        name: String,
        for space: TrackedSpace
    ) {
        commitRequest = CommitRequest(
            space: space, mode: .automatic(name: name, provider: provider))
    }

    @ViewBuilder
    private var detail: some View {
        if let space = selectedSpace {
            SpaceDetail(space: space)
        } else if app.spaces.isEmpty {
            ContentUnavailableView(
                app.localized("main.no_spaces"),
                systemImage: "square.stack.3d.up.slash",
                description: Text(app.localized("main.no_spaces_help")))
        } else {
            List {
                ForEach(app.groups) { group in
                    Section(group.id) {
                        ForEach(group.spaces) { space in
                            SpaceRow(space: space)
                        }
                    }
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } })
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { app.noticeMessage != nil },
            set: { if !$0 { app.noticeMessage = nil } })
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameSpace != nil },
            set: { if !$0 { renameSpace = nil } })
    }

    private var closeSessionTitle: String {
        guard let session = app.pendingCloseSession else {
            return app.localized("terminal.close_title")
        }
        return app.localized("terminal.close_named_title", session.agent.name)
    }

    private var closeSessionPresented: Binding<Bool> {
        Binding(
            get: { app.pendingCloseSessionID != nil },
            set: { if !$0 { app.cancelCloseSession() } })
    }
}

/// Sidebar row: space name plus a badge with the number of active agents; the
/// badge turns orange when an agent needs input.
private struct SidebarSpaceRow: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace
    @ObservedObject var manager: SessionManager
    let onCommit: () -> Void
    let onAutomaticCommit: (CommitMessageProvider, String) -> Void
    let onSwitchBranch: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label(
                    space.displayTitle,
                    systemImage: space.taskType == "folder" ? "folder" : "shippingbox")
                    .lineLimit(1)
                if let branch = app.currentBranch(for: space) {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            let running = manager.runningCount(for: space)
            if running > 0 {
                Text("\(running)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeColor))
                    .foregroundStyle(.white)
                    .help(badgeHelp(running: running))
            }
            if space.taskType != "folder" {
                Menu {
                    Button(app.localized("git.create_commit"), action: onCommit)
                    Menu(app.localized("git.automatic_commit")) {
                        Button("Claude") { onAutomaticCommit(.claude, "Claude") }
                        Button("Codex") { onAutomaticCommit(.codex, "Codex") }
                        if !app.commitGenerators.isEmpty {
                            Divider()
                            ForEach(app.commitGenerators) { generator in
                                Button(generator.name) {
                                    onAutomaticCommit(
                                        .custom(command: generator.command), generator.name)
                                }
                                .disabled(generator.command
                                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    Divider()
                    Button(app.localized("git.switch_branch"), action: onSwitchBranch)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    /// Orange (needs you) wins over indigo (working) over green (idle).
    private var badgeColor: Color {
        if manager.needsAttention(space) { return .orange }
        if manager.isWorking(space) { return .indigo }
        return .green.opacity(0.8)
    }

    private func badgeHelp(running: Int) -> String {
        if manager.needsAttention(space) { return app.localized("main.agent_needs_input") }
        if manager.isWorking(space) { return app.localized("main.agent_working") }
        return app.localized("main.active_agents", running)
    }
}

/// Detail of a space: metadata header + terminal area of its agent sessions.
private struct SpaceDetail: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace

    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalPane(manager: app.sessionManager, space: space)
        }
        .confirmationDialog(
            app.localized("main.delete_title", space.displayTitle),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(app.localized("common.delete"), role: .destructive) { app.delete(space) }
            Button(app.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        let running = app.sessionManager.runningCount(for: space)
        if running > 0 {
            return app.localized("main.delete_folder_agents", space.destination, running)
        }
        return app.localized("main.delete_folder", space.destination)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayTitle).font(.headline)
                Label(
                    space.taskType == "folder"
                        ? app.localized("main.folder_copy")
                        : app.currentBranch(for: space) ?? app.localized("git.unknown_branch"),
                    systemImage: space.taskType == "folder" ? "folder" : "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(space.destination)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            Menu(app.localized("main.open_in")) {
                ForEach(Editor.allCases) { editor in
                    Button(editor.displayName) { app.open(editor, space) }
                }
            }
            .fixedSize()
            HStack(spacing: 8) {
                Button("Finder", systemImage: "folder") { app.reveal(space) }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(app.localized("common.delete"), systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A single space row of the overview list, with metadata and inline actions.
struct SpaceRow: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace

    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(space.displayTitle).font(.headline)
                Label(
                    space.taskType == "folder"
                        ? app.localized("main.folder_copy")
                        : app.currentBranch(for: space) ?? app.localized("git.unknown_branch"),
                    systemImage: space.taskType == "folder" ? "folder" : "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(space.destination)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text(app.localized(
                    "main.created_on",
                    formatCreatedAt(space.createdAt, locale: app.appLanguage.locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    LaunchAgentMenu(space: space) {
                        Label(app.localized("main.launch_agent"), systemImage: "play.fill")
                    }
                    .fixedSize()
                    Menu(app.localized("main.open_in")) {
                        ForEach(Editor.allCases) { editor in
                            Button(editor.displayName) { app.open(editor, space) }
                        }
                    }
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    Button("Finder", systemImage: "folder") { app.reveal(space) }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label(app.localized("common.delete"), systemImage: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            app.localized("main.delete_title", space.displayTitle),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(app.localized("common.delete"), role: .destructive) { app.delete(space) }
            Button(app.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(app.localized("main.delete_folder", space.destination))
        }
    }
}
