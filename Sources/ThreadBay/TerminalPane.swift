import AppKit
import ThreadBayCore
import SwiftUI

/// Terminal area of a space: a tab-like selector for the space's sessions
/// (decision n°2 allows several) and the embedded terminal of the selected
/// session.
struct TerminalPane: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var manager: SessionManager
    let space: TrackedSpace

    /// Key-window state: a badge is only acknowledged when the user can
    /// actually see the terminal.
    @Environment(\.controlActiveState) private var activeState
    @State private var launchMenuRequest = 0
    @State private var launchMenuLocation = NSPoint.zero
    @State private var renameSession: AgentSession?
    @State private var renameText = ""

    private var sessions: [AgentSession] {
        manager.sessions(for: space)
    }

    /// The last selected session in this space, else its first session.
    private var current: AgentSession? {
        manager.selectedSession(for: space)
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    sessionBar
                    Divider()
                    if let session = current {
                        TerminalHostView(session: session)
                            .id(session.id)
                    }
                }
            }
        }
        // Covers every deliberate "the user now sees this session" path:
        // space opened from the sidebar, tab switch, and window refocus.
        .onAppear { acknowledgeIfVisible() }
        .onChange(of: current?.id) { _, _ in acknowledgeIfVisible() }
        .onChange(of: activeState) { _, _ in acknowledgeIfVisible() }
        .alert(
            app.localized("terminal.rename_title", renameSession?.displayName ?? ""),
            isPresented: Binding(presence: $renameSession)
        ) {
            TextField(app.localized("terminal.tab_name"), text: $renameText)
            Button(app.localized("common.cancel"), role: .cancel) { renameSession = nil }
            Button(app.localized("management.rename")) {
                renameSession?.customName = renameText
                renameSession = nil
            }
        }
    }

    /// A running agent goes through the Cmd+W confirmation dialog; a finished
    /// one closes immediately.
    private func requestClose(_ session: AgentSession) {
        if session.state.isActive {
            app.pendingCloseSessionID = session.id
        } else {
            manager.close(session)
        }
    }

    private func acknowledgeIfVisible() {
        guard activeState != .inactive, let session = current else { return }
        manager.acknowledge(session)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(app.localized("terminal.no_agent"), systemImage: "terminal")
        } description: {
            Text(app.localized("terminal.no_agent_help"))
        } actions: {
            LaunchAgentMenu(space: space) {
                Label(app.localized("main.launch_agent"), systemImage: "play.fill")
            }
            .fixedSize()
        }
    }

    private var sessionBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sessions) { session in
                        SessionTab(
                            session: session,
                            isSelected: session.id == current?.id,
                            select: { manager.select(session.id) },
                            close: { requestClose(session) },
                            rename: {
                                renameText = session.displayName
                                renameSession = session
                            })
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    launchMenuLocation = NSEvent.mouseLocation
                    launchMenuRequest += 1
                })
            Spacer()
            AgentLaunchPopUpButton(
                agents: app.agents,
                requestID: launchMenuRequest,
                menuLocation: launchMenuLocation,
                help: app.localized("terminal.launch_another"),
                launch: { app.launchAgent($0, in: space) })
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// One session "tab": status dot, session name and close button.
private struct SessionTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: AgentSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    let rename: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.statusColor)
                .frame(width: 7, height: 7)
            Text(session.displayName)
                .lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(app.localized("terminal.close_tab"))
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .contextMenu {
            Button {
                rename()
            } label: {
                Label(app.localized("terminal.rename_tab"), systemImage: "pencil")
            }
        }
        .help(session.stateDescription(language: app.appLanguage))
    }
}

/// Menu offering the configured agents for a space.
struct LaunchAgentMenu<Label: View>: View {
    @EnvironmentObject var app: AppState
    let space: TrackedSpace
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(app.agents) { agent in
                Button(agent.name) { app.launchAgent(agent, in: space) }
            }
        } label: {
            label()
        }
    }
}

/// AppKit pull-down button so a double-click on the tab row can open the exact
/// same menu as the + button.
private struct AgentLaunchPopUpButton: NSViewRepresentable {
    let agents: [AgentDefinition]
    let requestID: Int
    let menuLocation: NSPoint
    let help: String
    let launch: (AgentDefinition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(launch: launch)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.imagePosition = .imageOnly
        context.coordinator.configure(button, agents: agents, help: help)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.launch = launch
        context.coordinator.configure(button, agents: agents, help: help)
        guard requestID != context.coordinator.lastRequestID else { return }
        context.coordinator.lastRequestID = requestID
        DispatchQueue.main.async {
            button.menu?.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var launch: (AgentDefinition) -> Void
        var lastRequestID = 0
        private var agents: [AgentDefinition] = []

        init(launch: @escaping (AgentDefinition) -> Void) {
            self.launch = launch
        }

        func configure(_ button: NSPopUpButton, agents: [AgentDefinition], help: String) {
            button.toolTip = help
            guard self.agents != agents || button.numberOfItems == 0 else { return }
            self.agents = agents
            button.removeAllItems()
            button.addItem(withTitle: "")
            button.item(at: 0)?.image = NSImage(
                systemSymbolName: "plus", accessibilityDescription: help)
            for (index, agent) in agents.enumerated() {
                let item = NSMenuItem(
                    title: agent.name,
                    action: #selector(launchAgent(_:)),
                    keyEquivalent: "")
                item.target = self
                item.tag = index
                button.menu?.addItem(item)
            }
        }

        @objc private func launchAgent(_ item: NSMenuItem) {
            guard agents.indices.contains(item.tag) else { return }
            launch(agents[item.tag])
        }
    }
}

extension AgentSession {
    var statusColor: Color {
        switch attention {
        case .needsInput: return .orange
        case .turnEnded: return .blue
        case .sessionEnded: return .gray
        case .none:
            guard state.isActive else { return .gray }
            return isWorking ? .indigo : .green
        }
    }

    func stateDescription(language: AppLanguage) -> String {
        switch state {
        case .starting:
            return L10n.string("terminal.starting", language: language)
        case .running:
            switch attention {
            case .needsInput:
                return L10n.string("terminal.needs_input", language: language)
            case .turnEnded:
                return L10n.string("terminal.turn_completed", language: language)
            default:
                return L10n.string(
                    isWorking ? "terminal.working" : "terminal.running",
                    language: language)
            }
        case .exited(let code):
            if let code {
                return L10n.string(
                    "terminal.finished_code", language: language, arguments: [code])
            }
            return L10n.string("terminal.finished", language: language)
        }
    }
}
