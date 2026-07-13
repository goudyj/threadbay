import AppKit
import OrchestrateCore
import SwiftUI

/// Main window: spaces sidebar (with agent badges) + detail area showing the
/// selected space and its embedded agent terminals. Also hosts the create and
/// settings sheets, and drives the Dock/activation policy while visible.
struct MainWindow: View {
    @EnvironmentObject var app: AppState

    /// "" means the overview of all spaces; otherwise the selected space name.
    @State private var selection = ""
    @State private var showNew = false
    @State private var showSettings = false

    private var selectedSpace: TrackedSpace? {
        app.spaces.first { $0.name == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Tous les espaces", systemImage: "square.stack.3d.up")
                        .tag("")
                    ForEach(app.groups) { group in
                        Section(group.id) {
                            ForEach(group.spaces) { space in
                                SidebarSpaceRow(space: space, manager: app.sessionManager)
                                    .tag(space.name)
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
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(app) }
        .onAppear {
            app.reload()
            applyPending()
        }
        .onChange(of: app.pendingNewSpace) { _, _ in applyPending() }
        .onChange(of: app.pendingSettings) { _, _ in applyPending() }
        .onChange(of: app.pendingSelectSpace) { _, _ in applyPending() }
        .alert("Erreur", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { showNew = true } label: {
                Label("Nouvel espace", systemImage: "plus")
            }
            .disabled(app.settings.projects.isEmpty)
            Spacer()
            Button { app.reload() } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            Button { showSettings = true } label: {
                Label("Réglages", systemImage: "gearshape")
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
            selection = name
            app.pendingSelectSpace = nil
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let space = selectedSpace {
            SpaceDetail(space: space)
        } else if app.spaces.isEmpty {
            ContentUnavailableView(
                "Aucun espace",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Crée un espace avec le bouton + de la barre d'outils."))
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
}

/// Sidebar row: space name plus a badge with the number of active agents; the
/// badge turns orange when an agent needs input.
private struct SidebarSpaceRow: View {
    let space: TrackedSpace
    @ObservedObject var manager: SessionManager

    var body: some View {
        HStack {
            Label(space.name, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
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
        }
    }

    /// Orange (needs you) wins over indigo (working) over green (idle).
    private var badgeColor: Color {
        if manager.needsAttention(space) { return .orange }
        if manager.isWorking(space) { return .indigo }
        return .green.opacity(0.8)
    }

    private func badgeHelp(running: Int) -> String {
        if manager.needsAttention(space) { return "Un agent a besoin de toi" }
        if manager.isWorking(space) { return "Un agent réfléchit…" }
        return "\(running) agent(s) actif(s)"
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
            "Supprimer « \(space.name) » ?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { app.delete(space) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        let running = app.sessionManager.runningCount(for: space)
        let agents = running > 0 ? " \(running) agent(s) actif(s) seront arrêtés." : ""
        return "Le dossier \(space.destination) sera supprimé.\(agents)"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name).font(.headline)
                Label(space.taskValue, systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(space.destination)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            LaunchAgentMenu(space: space) {
                Label("Lancer un agent", systemImage: "play.fill")
            }
            .fixedSize()
            Menu("Ouvrir dans…") {
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
                    Label("Supprimer", systemImage: "trash")
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
                Text(space.name).font(.headline)
                Label(space.taskValue, systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(space.destination)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text("Créé le \(formatCreatedAt(space.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    LaunchAgentMenu(space: space) {
                        Label("Lancer un agent", systemImage: "play.fill")
                    }
                    .fixedSize()
                    Menu("Ouvrir dans…") {
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
                        Label("Supprimer", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Supprimer « \(space.name) » ?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { app.delete(space) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le dossier \(space.destination) sera supprimé.")
        }
    }
}
