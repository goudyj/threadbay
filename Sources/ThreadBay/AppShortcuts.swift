import AppKit
import Carbon.HIToolbox
import SwiftUI

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case newSpace
    case closeSession
    case launchClaude
    case launchCodex
    case launchShell

    var id: Self { self }
}

enum AppShortcutModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        case .command: return .command
        }
    }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }
}

struct AppShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var keyLabel: String
    var modifiers: [AppShortcutModifier]

    init(keyCode: Int, keyLabel: String, modifiers: [AppShortcutModifier]) {
        self.keyCode = UInt16(keyCode)
        self.keyLabel = keyLabel
        self.modifiers = AppShortcutModifier.allCases.filter(modifiers.contains)
    }

    init?(event: NSEvent) {
        let modifiers = AppShortcutModifier.allCases.filter {
            event.modifierFlags.contains($0.eventFlag)
        }
        // A plain key or Shift+key would steal normal terminal input.
        guard modifiers.contains(where: { $0 != .shift }) else { return nil }
        guard let keyLabel = Self.keyLabel(for: event), !keyLabel.isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), keyLabel: keyLabel, modifiers: modifiers)
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = AppShortcutModifier.allCases.filter {
            event.modifierFlags.contains($0.eventFlag)
        }
        return matchesKey(event) && eventModifiers == modifiers
    }

    var displayName: String {
        modifiers.map(\.symbol).joined() + keyLabel
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Tab: return "⇥"
        case kVK_Return: return "↩"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return event.charactersIgnoringModifiers?.uppercased()
        }
    }

    private func matchesKey(_ event: NSEvent) -> Bool {
        guard keyLabel.count == 1, keyLabel.first?.isLetter == true else {
            return event.keyCode == keyCode
        }
        return event.charactersIgnoringModifiers?.uppercased() == keyLabel.uppercased()
    }

    fileprivate func hasSameKey(as other: AppShortcut) -> Bool {
        if keyLabel.count == 1, keyLabel.first?.isLetter == true,
            other.keyLabel.count == 1, other.keyLabel.first?.isLetter == true {
            return keyLabel.uppercased() == other.keyLabel.uppercased()
        }
        return keyCode == other.keyCode
    }
}

struct AppShortcutSettings: Codable, Equatable, Sendable {
    static let defaultsKey = "appShortcuts"

    var newSpace = AppShortcut(
        keyCode: kVK_ANSI_N, keyLabel: "N", modifiers: [.command])
    var closeSession = AppShortcut(
        keyCode: kVK_ANSI_W, keyLabel: "W", modifiers: [.command])
    var launchClaude = AppShortcut(
        keyCode: kVK_ANSI_1, keyLabel: "1", modifiers: [.shift, .command])
    var launchCodex = AppShortcut(
        keyCode: kVK_ANSI_2, keyLabel: "2", modifiers: [.shift, .command])
    var launchShell = AppShortcut(
        keyCode: kVK_ANSI_3, keyLabel: "3", modifiers: [.shift, .command])

    subscript(action: AppShortcutAction) -> AppShortcut {
        get {
            switch action {
            case .newSpace: return newSpace
            case .closeSession: return closeSession
            case .launchClaude: return launchClaude
            case .launchCodex: return launchCodex
            case .launchShell: return launchShell
            }
        }
        set {
            switch action {
            case .newSpace: newSpace = newValue
            case .closeSession: closeSession = newValue
            case .launchClaude: launchClaude = newValue
            case .launchCodex: launchCodex = newValue
            case .launchShell: launchShell = newValue
            }
        }
    }

    func action(matching event: NSEvent) -> AppShortcutAction? {
        AppShortcutAction.allCases.first { self[$0].matches(event) }
    }

    func conflictingAction(
        for shortcut: AppShortcut,
        excluding action: AppShortcutAction
    ) -> AppShortcutAction? {
        AppShortcutAction.allCases.first {
            $0 != action
                && self[$0].hasSameKey(as: shortcut)
                && self[$0].modifiers == shortcut.modifiers
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
            let settings = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: AppShortcut

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = { shortcut = $0 }
        button.update(shortcut)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = { shortcut = $0 }
        button.update(shortcut)
    }
}

final class ShortcutRecorderButton: NSButton {
    var onChange: ((AppShortcut) -> Void)?
    private var shortcut: AppShortcut?
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func update(_ shortcut: AppShortcut) {
        self.shortcut = shortcut
        if !isRecording {
            title = shortcut.displayName
        }
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }
        guard let shortcut = AppShortcut(event: event) else {
            NSSound.beep()
            return
        }
        onChange?(shortcut)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        title = shortcut?.displayName ?? ""
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        title = shortcut?.displayName ?? ""
        window?.makeFirstResponder(nil)
    }
}
