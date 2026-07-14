import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
}

public enum ShellError: Error, LocalizedError {
    case toolNotFound(String)
    case commandFailed(command: String, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "Outil introuvable : « \(tool) ». Vérifie qu'il est installé et dans le PATH."
        case .commandFailed(let command, let stderr):
            let detail = stderr.isEmpty ? "" : "\n\(stderr)"
            return "Échec de la commande : \(command)\(detail)"
        }
    }
}

/// Runs external tools (`git`, editors, `open`). A GUI app launched from Finder
/// does not inherit the shell PATH, so tool locations are resolved once via a
/// login shell and cached, and every command runs with an augmented PATH.
public final class Shell: @unchecked Sendable {
    public static let shared = Shell()

    private let lock = NSLock()
    private var toolCache: [String: String] = [:]

    private static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    private static let augmentedPATH = searchDirs.joined(separator: ":")

    public init() {}

    /// Absolute path of `tool`, resolved via `zsh -lc 'command -v'` then a scan
    /// of the usual bin directories. Cached across calls.
    public func resolve(_ tool: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = toolCache[tool] { return cached }

        if let viaLogin = Self.loginShellLookup(tool) {
            toolCache[tool] = viaLogin
            return viaLogin
        }
        for dir in Self.searchDirs {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                toolCache[tool] = candidate
                return candidate
            }
        }
        throw ShellError.toolNotFound(tool)
    }

    /// Runs `tool args…` in `cwd`, capturing output. Reads stdout/stderr on
    /// background threads to avoid pipe-buffer deadlocks.
    @discardableResult
    public func run(
        _ tool: String,
        _ args: [String],
        cwd: URL? = nil,
        input: String? = nil
    ) throws -> CommandResult {
        let executable = try resolve(tool)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }

        var env = ProcessInfo.processInfo.environment
        let existingPATH = env["PATH"] ?? ""
        env["PATH"] = existingPATH.isEmpty
            ? Self.augmentedPATH : "\(Self.augmentedPATH):\(existingPATH)"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inputPipe = input == nil ? nil : Pipe()
        process.standardInput = inputPipe

        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }

        // Read stderr on a background queue while stdout is drained on this
        // thread, so neither pipe buffer can fill and deadlock the child.
        let errBox = DataBox()
        let queue = DispatchQueue(label: "threadbay.shell.read")
        queue.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        queue.sync {}  // barrier: the stderr read has completed
        let errData = errBox.data
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Like `run`, but throws `ShellError.commandFailed` on a non-zero exit.
    @discardableResult
    public func check(
        _ tool: String,
        _ args: [String],
        cwd: URL? = nil,
        input: String? = nil
    ) throws -> String {
        let result = try run(tool, args, cwd: cwd, input: input)
        guard result.isSuccess else {
            throw ShellError.commandFailed(
                command: "\(tool) \(args.joined(separator: " "))", stderr: result.stderr)
        }
        return result.stdout
    }

    /// Reference box so a captured `let` (not a `var`) is mutated across queues.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private static func loginShellLookup(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(tool)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
