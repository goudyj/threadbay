import AppKit
import ThreadBayCore
import SwiftUI

/// Application settings, including app-only preferences and a shortcut to edit
/// the raw `settings.yaml` managed jointly with the CLI.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.localized("settings.title"))
                .font(.title2)
                .bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        Picker(app.localized("settings.language"), selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(languageName(language)).tag(language)
                            }
                        }

                        Picker(
                            app.localized("settings.default_project"),
                            selection: defaultBinding
                        ) {
                            Text(app.localized("common.none")).tag(String?.none)
                            ForEach(app.settings.projects) {
                                Text($0.name).tag(Optional($0.name))
                            }
                        }
                    }

                    Text(app.localized("settings.projects")).font(.headline)
                    if app.settings.projects.isEmpty {
                        Text(app.localized("settings.no_projects"))
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(app.settings.projects) { project in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(project.name)
                                        Text(project.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        app.removeProject(project.name)
                                    } label: {
                                        Label(
                                            app.localized("common.remove"), systemImage: "trash")
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

                    Text(app.localized("settings.commit_generators")).font(.headline)
                    CommitGeneratorsEditor()

                    Text(app.localized("settings.shortcuts")).font(.headline)
                    VStack(spacing: 8) {
                        ForEach(AppShortcutAction.allCases) { action in
                            HStack {
                                Text(shortcutName(action))
                                Spacer()
                                ShortcutRecorder(shortcut: shortcutBinding(action))
                                    .frame(width: 90)
                            }
                        }
                    }
                    Text(app.localized("settings.shortcuts_help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(app.localized("settings.shortcuts_reset")) { app.resetShortcuts() }

                    Text(app.localized("settings.terminal")).font(.headline)
                    Picker(
                        app.localized("settings.appearance"),
                        selection: terminalThemeBinding
                    ) {
                        Text(app.localized("settings.theme.system")).tag(TerminalTheme.system)
                        Text(app.localized("settings.theme.light")).tag(TerminalTheme.light)
                        Text(app.localized("settings.theme.dark")).tag(TerminalTheme.dark)
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack {
                Spacer()
                Button(app.localized("common.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 700)
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

    private func shortcutName(_ action: AppShortcutAction) -> String {
        switch action {
        case .newSpace: return app.localized("settings.shortcut_new_space")
        case .closeSession: return app.localized("settings.shortcut_close_session")
        case .launchClaude: return app.localized("settings.shortcut_claude")
        case .launchCodex: return app.localized("settings.shortcut_codex")
        case .launchShell: return app.localized("settings.shortcut_shell")
        }
    }

    private func shortcutBinding(_ action: AppShortcutAction) -> Binding<AppShortcut> {
        Binding(
            get: { app.shortcuts[action] },
            set: { app.setShortcut($0, for: action) })
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

private struct CommitGeneratorsEditor: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            ForEach(app.commitGenerators.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(
                        app.localized("settings.generator_name"),
                        text: binding(index).name)
                        .frame(width: 130)
                    TextField(
                        app.localized("settings.generator_command"),
                        text: binding(index).command)
                        .font(.body.monospaced())
                    Button(role: .destructive) {
                        app.commitGenerators.remove(at: index)
                        app.persistAgents()
                    } label: {
                        Label(app.localized("common.remove"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(minHeight: 100)

        HStack {
            Button(app.localized("settings.add_generator")) {
                let name = Naming.ensureUniqueName(
                    base: app.localized("settings.new_generator"), separator: " "
                ) { candidate in
                    app.commitGenerators.contains { $0.name == candidate }
                }
                app.commitGenerators.append(
                    CommitGeneratorDefinition(name: name, command: ""))
                app.persistAgents()
            }
            Spacer()
            Text(app.localized("settings.generator_help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(_ index: Int) -> Binding<CommitGeneratorDefinition> {
        Binding(
            get: { app.commitGenerators[index] },
            set: {
                app.commitGenerators[index] = $0
                app.persistAgents()
            })
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
                let name = Naming.ensureUniqueName(
                    base: app.localized("settings.new_agent"), separator: " "
                ) { candidate in
                    app.agents.contains { $0.name == candidate }
                }
                app.agents.append(
                    AgentDefinition(name: name, command: "", kind: .custom))
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

}
