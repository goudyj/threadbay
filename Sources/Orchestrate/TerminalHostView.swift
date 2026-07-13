import AppKit
import SwiftTerm
import SwiftUI

/// Hosts a session's `LocalProcessTerminalView` in SwiftUI. The terminal view
/// is owned by the `AgentSession` (it must outlive the SwiftUI view so the
/// scrollback and the PTY survive selection changes); this wrapper only
/// attaches it to the hierarchy and hands it keyboard focus.
struct TerminalHostView: NSViewRepresentable {
    let session: AgentSession

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminal = session.terminalView
        guard terminal.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
    }
}
