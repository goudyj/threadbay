import OrchestrateCore
import SwiftUI

/// Terminal area of a space: a tab-like selector for the space's sessions
/// (decision n°2 allows several), a restart/stop/clear action bar, and the
/// embedded terminal of the selected session.
struct TerminalPane: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var manager: SessionManager
    let space: TrackedSpace

    /// Key-window state: a badge is only acknowledged when the user can
    /// actually see the terminal.
    @Environment(\.controlActiveState) private var activeState

    private var sessions: [AgentSession] {
        manager.sessions(for: space)
    }

    /// The globally selected session when it belongs to this space, else the
    /// first session of the space.
    private var current: AgentSession? {
        sessions.first { $0.id == manager.selectedID } ?? sessions.first
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
        // Covers every "the user now sees this session" path: space opened
        // from the sidebar, tab switch, window refocus, and an event landing
        // while the session is already on screen.
        .onAppear { acknowledgeIfVisible() }
        .onChange(of: current?.id) { _, _ in acknowledgeIfVisible() }
        .onChange(of: current?.attention) { _, _ in acknowledgeIfVisible() }
        .onChange(of: activeState) { _, _ in acknowledgeIfVisible() }
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
                            close: { manager.close(session) })
                    }
                }
            }
            Spacer()
            if let session = current {
                SessionActions(session: session)
            }
            LaunchAgentMenu(space: space) {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(app.localized("terminal.launch_another"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// One session "tab": status dot, agent name, close button.
private struct SessionTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: AgentSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.statusColor)
                .frame(width: 7, height: 7)
            Text(session.agent.name)
                .lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(app.localized("terminal.close_session"))
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .help(session.stateDescription(language: app.appLanguage))
    }
}

/// Restart / stop / clear buttons for the selected session.
private struct SessionActions: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: AgentSession

    var body: some View {
        HStack(spacing: 2) {
            Button {
                session.restart()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(app.localized("terminal.restart"))
            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!session.state.isActive)
            .help(app.localized("terminal.stop"))
            Button {
                session.clear()
            } label: {
                Image(systemName: "clear")
            }
            .help(app.localized("terminal.clear"))
        }
        .buttonStyle(.borderless)
    }
}

/// Menu offering the configured agents for a space (used from the empty state,
/// the session bar, the space rows and the menu bar).
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
