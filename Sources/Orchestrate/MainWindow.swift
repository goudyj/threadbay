import AppKit
import OrchestrateCore
import SwiftUI

/// Main window: projects sidebar + detailed spaces list. Also hosts the create
/// and settings sheets, and drives the Dock/activation policy while visible.
struct MainWindow: View {
    @EnvironmentObject var app: AppState

    /// "" means "all projects".
    @State private var selection = ""
    @State private var showNew = false
    @State private var showSettings = false

    private var visibleGroups: [AppState.ProjectGroup] {
        selection.isEmpty ? app.groups : app.groups.filter { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Tous les espaces", systemImage: "square.stack.3d.up")
                        .tag("")
                    Section("Projets") {
                        ForEach(app.settings.projects) { project in
                            Label(project.name, systemImage: "folder").tag(project.name)
                        }
                    }
                }
                .frame(minWidth: 200)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .sheet(isPresented: $showNew) { NewSpaceView().environmentObject(app) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(app) }
        .onAppear {
            app.reload()
            applyPending()
        }
        .onChange(of: app.pendingNewSpace) { _, _ in applyPending() }
        .onChange(of: app.pendingSettings) { _, _ in applyPending() }
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
    }

    @ViewBuilder
    private var detail: some View {
        if app.spaces.isEmpty {
            ContentUnavailableView(
                "Aucun espace",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Crée un espace avec le bouton + de la barre d'outils."))
        } else {
            List {
                ForEach(visibleGroups) { group in
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

/// A single space row with metadata and inline actions.
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
