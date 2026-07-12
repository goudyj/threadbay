import AppKit
import OrchestrateCore
import SwiftUI

/// Minimal settings: default project + project list, plus a shortcut to edit the
/// raw `settings.yaml` (parity with the CLI's `orchestrate settings`).
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Réglages").font(.title2).bold()

            Form {
                Picker("Projet par défaut", selection: defaultBinding) {
                    Text("Aucun").tag(String?.none)
                    ForEach(app.settings.projects) { Text($0.name).tag(Optional($0.name)) }
                }
            }

            Text("Projets").font(.headline)
            if app.settings.projects.isEmpty {
                Text("Aucun projet.").foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(app.settings.projects) { project in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(project.name)
                                Text(project.path).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                app.removeProject(project.name)
                            } label: {
                                Label("Retirer", systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 120)
            }

            HStack {
                Button("Ajouter un projet…") { addProject() }
                Button("Ouvrir settings.yaml") { app.openSettingsFile() }
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private var defaultBinding: Binding<String?> {
        Binding(
            get: { app.settings.defaultProject },
            set: { app.setDefaultProject($0) })
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ajouter"
        panel.message = "Choisis le dossier du dépôt git source"
        if panel.runModal() == .OK, let url = panel.url {
            app.addProject(path: url)
        }
    }
}
