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
    @State private var spaceToDelete: TrackedSpace?
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
                                    onSwitchBranch: { branchSwitchSpace = space },
                                    onRename: { presentRename(for: space) },
                                    onDelete: { spaceToDelete = space })
                                    .tag(space.name)
                                    .contextMenu {
                                        SidebarSpaceActions(
                                            space: space,
                                            onCommit: { presentCommit(for: space) },
                                            onAutomaticCommit: {
                                                presentAutomaticCommit($0, name: $1, for: space)
                                            },
                                            onSwitchBranch: { branchSwitchSpace = space },
                                            onRename: { presentRename(for: space) },
                                            onDelete: { spaceToDelete = space })
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
        .alert(app.localized("main.error"), isPresented: Binding(presence: $app.errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .alert(app.localized("main.warning"), isPresented: Binding(presence: $app.noticeMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.noticeMessage ?? "")
        }
        .alert(app.localized("main.success"), isPresented: Binding(presence: $app.successMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.successMessage ?? "")
        }
        .renameSpaceAlert(space: $renameSpace, text: $renameText)
        .confirmDeleteSpace($spaceToDelete)
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

    private func presentRename(for space: TrackedSpace) {
        renameSpace = space
        renameText = space.displayTitle
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

    private var closeSessionTitle: String {
        guard let session = app.pendingCloseSession else {
            return app.localized("terminal.close_title")
        }
        return app.localized("terminal.close_named_title", session.displayName)
    }

    private var closeSessionPresented: Binding<Bool> {
        Binding(
            get: { app.pendingCloseSessionID != nil },
            set: { if !$0 { app.cancelCloseSession() } })
    }
}

/// "Automatic commit" submenu shared by the sidebar context menu and the
/// row's ellipsis menu.
private struct AutomaticCommitMenu: View {
    @EnvironmentObject var app: AppState
    let onSelect: (CommitMessageProvider, String) -> Void

    var body: some View {
        Menu(app.localized("git.automatic_commit")) {
            Button("Claude") { onSelect(.claude, "Claude") }
            Button("Codex") { onSelect(.codex, "Codex") }
            if !app.commitGenerators.isEmpty {
                Divider()
                ForEach(app.commitGenerators) { generator in
                    Button(generator.name) {
                        onSelect(.custom(command: generator.command), generator.name)
                    }
                    .disabled(generator.command
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// "Open in <editor>" menu shared by the detail header and the overview row.
private struct OpenInEditorMenu: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace

    var body: some View {
        Menu(app.localized("main.open_in")) {
            ForEach(Editor.allCases) { editor in
                Button(editor.displayName) { app.open(editor, space) }
            }
        }
        .fixedSize()
    }
}

/// Push / force-push pair shared by the sidebar context menu and the row's
/// ellipsis menu.
private struct PushMenuButtons: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace

    var body: some View {
        Button {
            Task { await app.push(in: space, forceWithLease: false) }
        } label: {
            Label(app.localized("git.push"), systemImage: "arrow.up.circle")
        }
        Button {
            Task { await app.push(in: space, forceWithLease: true) }
        } label: {
            Label(app.localized("git.push_force"), systemImage: "arrow.up.circle.badge.clock")
        }
    }
}

/// Actions shared by a sidebar row's context and ellipsis menus.
private struct SidebarSpaceActions: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace
    let onCommit: () -> Void
    let onAutomaticCommit: (CommitMessageProvider, String) -> Void
    let onSwitchBranch: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onRename) {
            Label(app.localized("management.rename"), systemImage: "pencil")
        }
        if space.supportsGitActions {
            Divider()
            Button(action: onCommit) {
                Label(app.localized("git.create_commit"), systemImage: "checkmark.circle")
            }
            AutomaticCommitMenu(onSelect: onAutomaticCommit)
            PushMenuButtons(space: space)
            Button(action: onSwitchBranch) {
                Label(
                    app.localized("git.switch_branch"),
                    systemImage: "arrow.triangle.branch")
            }
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(app.localized("common.delete"), systemImage: "trash")
        }
    }
}

/// Sidebar row: space name plus the number of unacknowledged session alerts.
private struct SidebarSpaceRow: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace
    @ObservedObject var manager: SessionManager
    let onCommit: () -> Void
    let onAutomaticCommit: (CommitMessageProvider, String) -> Void
    let onSwitchBranch: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label(space.displayTitle, systemImage: space.iconName)
                    .lineLimit(1)
                if let branch = app.currentBranch(for: space) {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            let attentionCount = manager.attentionCount(for: space)
            if attentionCount > 0 {
                Text("\(attentionCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeColor))
                    .foregroundStyle(.white)
                    .help(app.localized("main.unread_notifications", attentionCount))
            }
            Menu {
                SidebarSpaceActions(
                    space: space,
                    onCommit: onCommit,
                    onAutomaticCommit: onAutomaticCommit,
                    onSwitchBranch: onSwitchBranch,
                    onRename: onRename,
                    onDelete: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var badgeColor: Color {
        if manager.needsAttention(space) { return .orange }
        return .blue
    }
}

/// Detail of a space: metadata header + terminal area of its agent sessions.
private struct SpaceDetail: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace

    @State private var spaceToDelete: TrackedSpace?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalPane(manager: app.sessionManager, space: space)
        }
        .confirmDeleteSpace($spaceToDelete)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayTitle).font(.headline)
                Label(spaceSubtitle(space, app: app), systemImage: spaceSubtitleIcon(space))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(space.destination)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            OpenInEditorMenu(space: space)
            HStack(spacing: 8) {
                Button("Finder", systemImage: "folder") { app.reveal(space) }
                Button(role: .destructive) {
                    spaceToDelete = space
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

    @State private var spaceToDelete: TrackedSpace?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(space.displayTitle).font(.headline)
                Label(spaceSubtitle(space, app: app), systemImage: spaceSubtitleIcon(space))
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
                    OpenInEditorMenu(space: space)
                }
                HStack(spacing: 8) {
                    Button("Finder", systemImage: "folder") { app.reveal(space) }
                    Button(role: .destructive) {
                        spaceToDelete = space
                    } label: {
                        Label(app.localized("common.delete"), systemImage: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 4)
        .confirmDeleteSpace($spaceToDelete)
    }
}

extension TrackedSpace {
    var iconName: String {
        if isFolder { return "folder" }
        if isTerminal { return "terminal" }
        return "shippingbox"
    }
}

/// Second line under a space title: its branch, or the space's nature when
/// there is no repository to report on.
@MainActor
private func spaceSubtitle(_ space: TrackedSpace, app: AppState) -> String {
    if space.isFolder { return app.localized("main.folder_copy") }
    if space.isTerminal { return app.localized("main.terminal_space") }
    return app.branchLabel(for: space)
}

private func spaceSubtitleIcon(_ space: TrackedSpace) -> String {
    space.supportsGitActions ? "arrow.triangle.branch" : space.iconName
}
