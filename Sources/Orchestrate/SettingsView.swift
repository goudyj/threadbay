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
            }

            Divider()

            Text("Agents").font(.headline)
            AgentsEditor()

            Text("Terminal").font(.headline)
            Picker("Apparence", selection: terminalThemeBinding) {
                Text("Système").tag(TerminalTheme.system)
                Text("Clair").tag(TerminalTheme.light)
                Text("Sombre").tag(TerminalTheme.dark)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private var defaultBinding: Binding<String?> {
        Binding(
            get: { app.settings.defaultProject },
            set: { app.setDefaultProject($0) })
    }

    private var terminalThemeBinding: Binding<TerminalTheme> {
        Binding(
            get: { app.terminalTheme },
            set: { app.setTerminalTheme($0) })
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

/// Edits the agent catalogue (`agents.yaml`, app-only — decision n°3). Rows are
/// bound by index so renaming an agent does not reset the list identity.
private struct AgentsEditor: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            ForEach(app.agents.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Nom", text: binding(index).name)
                        .frame(width: 130)
                    TextField(
                        "Commande (vide = shell interactif)",
                        text: binding(index).command
                    )
                    .font(.body.monospaced())
                    Button(role: .destructive) {
                        app.agents.remove(at: index)
                        app.persistAgents()
                    } label: {
                        Label("Retirer", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(minHeight: 130)

        HStack {
            Button("Ajouter un agent") {
                app.agents.append(
                    AgentDefinition(name: uniqueName(), command: "", kind: .custom))
                app.persistAgents()
            }
            Spacer()
            Text("Placeholders : \(CommandTemplate.placeholders.joined(separator: " "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(_ index: Int) -> Binding<AgentDefinition> {
        Binding(
            get: { app.agents[index] },
            set: {
                app.agents[index] = $0
                app.persistAgents()
            })
    }

    private func uniqueName() -> String {
        var name = "Nouvel agent"
        var n = 2
        while app.agents.contains(where: { $0.name == name }) {
            name = "Nouvel agent \(n)"
            n += 1
        }
        return name
    }
}
