import AppKit
import SwiftUI

@main
struct OrchestrateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Orchestrate", systemImage: "square.stack.3d.up.fill") {
            MenuBarView().environmentObject(appDelegate.appState)
        }
    }
}

/// Menu-bar app (`.accessory`, no permanent Dock icon). The main window is an
/// AppKit-managed `NSWindow` so it reliably shows on launch and on reopen — a
/// SwiftUI `Window` scene does not show dependably in a `LSUIElement` app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var window: NSWindow?
    private var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let terminal = event.window?.firstResponder as? SessionTerminalView,
                terminal.handleShortcut(event)
            else { return event }
            return nil
        }
        appState.onShowWindow = { [weak self] in self?.showMainWindow() }
        appState.sessionManager.setUp()
        NSApp.setActivationPolicy(.accessory)
        showMainWindow()
    }

    /// Double-clicking the (already running) app reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// Decision n°4: warn when agents are still running, then kill them cleanly.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = appState.sessionManager.runningCount
        if running > 0 {
            let alert = NSAlert()
            alert.messageText = appState.localized("quit.title")
            alert.informativeText = appState.localized("quit.active_agents", running)
            alert.addButton(withTitle: appState.localized("quit.confirm"))
            alert.addButton(withTitle: appState.localized("common.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else {
                return .terminateCancel
            }
        }
        appState.sessionManager.tearDown()
        return .terminateNow
    }

    func showMainWindow() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MainWindow().environmentObject(appState))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Orchestrate"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1060, height: 640))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Back to a pure menu-bar app once the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
