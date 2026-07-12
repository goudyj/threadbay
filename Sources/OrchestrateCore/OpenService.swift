import Foundation

/// The editors the app can open a space in. Raw value is the CLI launcher.
public enum Editor: String, CaseIterable, Identifiable, Sendable {
    case vscode = "code"
    case zed = "zed"
    case cursor = "cursor"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .zed: return "Zed"
        case .cursor: return "Cursor"
        }
    }
}

/// Opens a space directory in an editor or in Finder.
public struct OpenService: Sendable {
    private let shell: Shell

    public init(shell: Shell = .shared) {
        self.shell = shell
    }

    public func open(_ editor: Editor, at path: String) throws {
        try shell.check(editor.rawValue, [path])
    }

    public func revealInFinder(_ path: String) throws {
        try shell.check("open", [path])
    }
}
