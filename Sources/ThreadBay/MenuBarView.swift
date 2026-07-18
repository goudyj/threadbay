import AppKit
import ThreadBayCore
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

    /// Suffixes the space name only when it has unacknowledged alerts.
    private func menuTitle(for space: TrackedSpace) -> String {
        let attentionCount = app.sessionManager.attentionCount(for: space)
        guard attentionCount > 0 else { return space.displayTitle }
        return app.localized("menu.unread_notifications", space.displayTitle, attentionCount)
    }
}
