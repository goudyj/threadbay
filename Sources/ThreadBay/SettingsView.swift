import AppKit
import ThreadBayCore
import SwiftUI

/// Minimal settings: default project + project list, plus a shortcut to edit the
/// raw `settings.yaml` (parity with the CLI's `threadbay settings`).
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.localized("settings.title")).font(.title2).bold()

            Form {
                Picker(app.localized("settings.language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageName(language)).tag(language)
                    }
                }

                Picker(app.localized("settings.default_project"), selection: defaultBinding) {
                    Text(app.localized("common.none")).tag(String?.none)
                    ForEach(app.settings.projects) { Text($0.name).tag(Optional($0.name)) }
                }
            }

            Text(app.localized("settings.projects")).font(.headline)
            if app.settings.projects.isEmpty {
                Text(app.localized("settings.no_projects")).foregroundStyle(.secondary)
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
                                Label(app.localized("common.remove"), systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 120)
            }

            HStack {
                Button(app.localized("settings.add_project")) { addProject() }
                Button(app.localized("settings.open_yaml")) { app.openSettingsFile() }
                Spacer()
            }

            Divider()

            Text(app.localized("settings.agents")).font(.headline)
            AgentsEditor()

            Text(app.localized("settings.terminal")).font(.headline)
            Picker(app.localized("settings.appearance"), selection: terminalThemeBinding) {
                Text(app.localized("settings.theme.system")).tag(TerminalTheme.system)
                Text(app.localized("settings.theme.light")).tag(TerminalTheme.light)
                Text(app.localized("settings.theme.dark")).tag(TerminalTheme.dark)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button(app.localized("common.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
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

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { app.appLanguage },
            set: { app.setAppLanguage($0) })
    }

    private func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system: return app.localized("language.system")
        case .english: return app.localized("language.english")
        case .french: return app.localized("language.french")
        case .spanish: return app.localized("language.spanish")
        case .simplifiedChinese: return app.localized("language.chinese")
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = app.localized("settings.add")
        panel.message = app.localized("settings.choose_repo")
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
                    TextField(app.localized("settings.agent_name"), text: binding(index).name)
                        .frame(width: 130)
                    TextField(
                        app.localized("settings.agent_command"),
                        text: binding(index).command
                    )
                    .font(.body.monospaced())
                    Button(role: .destructive) {
                        app.agents.remove(at: index)
                        app.persistAgents()
                    } label: {
                        Label(app.localized("common.remove"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(minHeight: 130)

        HStack {
            Button(app.localized("settings.add_agent")) {
                app.agents.append(
                    AgentDefinition(name: uniqueName(), command: "", kind: .custom))
                app.persistAgents()
            }
            Spacer()
            Text(app.localized(
                "settings.placeholders", CommandTemplate.placeholders.joined(separator: " ")))
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
        let baseName = app.localized("settings.new_agent")
        var name = baseName
        var n = 2
        while app.agents.contains(where: { $0.name == name }) {
            name = "\(baseName) \(n)"
            n += 1
        }
        return name
    }
}
