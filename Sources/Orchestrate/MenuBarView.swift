import AppKit
import OrchestrateCore
import SwiftUI

/// Content of the menu-bar item: spaces grouped by project, each with quick
/// actions, plus global commands.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.spaces.isEmpty {
            Text(app.localized("menu.no_spaces"))
        } else {
            ForEach(app.groups) { group in
                Section(group.id) {
                    ForEach(group.spaces) { space in
                        Menu(menuTitle(for: space)) {
                            ForEach(app.agents) { agent in
                                Button(app.localized("menu.launch", agent.name)) {
                                    app.launchAgent(agent, in: space)
                                }
                            }
                            Divider()
                            ForEach(Editor.allCases) { editor in
                                Button(app.localized("menu.open_in", editor.displayName)) {
                                    app.open(editor, space)
                                }
                            }
                            Divider()
                            Button(app.localized("menu.reveal_finder")) { app.reveal(space) }
                            Divider()
                            Button(app.localized("common.delete")) { app.delete(space) }
                        }
                    }
                }
            }
        }

        Divider()

        Button(app.localized("menu.new_space")) {
            app.pendingNewSpace = true
            app.showMainWindow()
        }
        Button(app.localized("menu.open_window")) { app.showMainWindow() }
        Button(app.localized("common.refresh")) { app.reload() }
        Button(app.localized("menu.settings")) {
            app.pendingSettings = true
            app.showMainWindow()
        }

        Divider()

        Button(app.localized("menu.quit")) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Suffixes the space name with its number of active agents.
    private func menuTitle(for space: TrackedSpace) -> String {
        let running = app.sessionManager.runningCount(for: space)
        guard running > 0 else { return space.name }
        let alert = app.sessionManager.needsAttention(space) ? " ⚠" : ""
        return app.localized("menu.active_agents", space.name, running) + alert
    }
}
