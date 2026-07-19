import ThreadBayCore
import SwiftUI

extension Binding where Value == Bool {
    /// Presents while `item` is non-nil; dismissal clears it.
    init<T: Sendable>(presence item: Binding<T?>) {
        self.init(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// Rename-space alert shared by the main window and the management sheet.
private struct RenameSpaceAlert: ViewModifier {
    @EnvironmentObject var app: AppState
    @Binding var space: TrackedSpace?
    @Binding var text: String

    func body(content: Content) -> some View {
        content.alert(
            app.localized("management.rename_title", space?.displayTitle ?? ""),
            isPresented: Binding(presence: $space)
        ) {
            TextField(app.localized("management.display_name"), text: $text)
            Button(app.localized("common.cancel"), role: .cancel) { space = nil }
            Button(app.localized("management.rename")) {
                if let space { app.rename(space, displayName: text) }
                space = nil
            }
        } message: {
            Text(app.localized("management.rename_help"))
        }
    }
}

/// Delete-space confirmation shared by the detail header, the overview row,
/// and the management sheet.
private struct ConfirmDeleteSpace: ViewModifier {
    @EnvironmentObject var app: AppState
    @Binding var space: TrackedSpace?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            app.localized("main.delete_title", space?.displayTitle ?? ""),
            isPresented: Binding(presence: $space),
            titleVisibility: .visible
        ) {
            Button(app.localized("common.delete"), role: .destructive) {
                if let space { app.delete(space) }
                space = nil
            }
            Button(app.localized("common.cancel"), role: .cancel) { space = nil }
        } message: {
            Text(space.map { app.deleteConfirmationMessage(for: $0) } ?? "")
        }
    }
}

extension View {
    func renameSpaceAlert(space: Binding<TrackedSpace?>, text: Binding<String>) -> some View {
        modifier(RenameSpaceAlert(space: space, text: text))
    }

    func confirmDeleteSpace(_ space: Binding<TrackedSpace?>) -> some View {
        modifier(ConfirmDeleteSpace(space: space))
    }
}
