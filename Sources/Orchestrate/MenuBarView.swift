import AppKit
import OrchestrateCore
import SwiftUI

/// Content of the menu-bar item: spaces grouped by project, each with quick
/// actions, plus global commands.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.spaces.isEmpty {
            Text("Aucun espace")
        } else {
            ForEach(app.groups) { group in
                Section(group.id) {
                    ForEach(group.spaces) { space in
                        Menu(space.name) {
                            ForEach(Editor.allCases) { editor in
                                Button("Ouvrir dans \(editor.displayName)") {
                                    app.open(editor, space)
                                }
                            }
                            Divider()
                            Button("Révéler dans le Finder") { app.reveal(space) }
                            Divider()
                            Button("Supprimer") { app.delete(space) }
                        }
                    }
                }
            }
        }

        Divider()

        Button("Nouvel espace…") {
            app.pendingNewSpace = true
            app.showMainWindow()
        }
        Button("Ouvrir la fenêtre") { app.showMainWindow() }
        Button("Rafraîchir") { app.reload() }
        Button("Réglages…") {
            app.pendingSettings = true
            app.showMainWindow()
        }

        Divider()

        Button("Quitter Orchestrate") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
