import Darwin
import Foundation

/// Watches a repository's HEAD for branch changes without polling Git.
final class GitHeadMonitor: @unchecked Sendable {
    private let headFile: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "threadbay.git-head-monitor")
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    init(repository: URL, onChange: @escaping @Sendable () -> Void) {
        headFile = Self.headFile(for: repository)
        self.onChange = onChange
    }

    /// Returns false when HEAD cannot be watched, leaving existing refresh
    /// paths (selection, activation, manual refresh) as the fallback.
    func start() -> Bool {
        queue.sync { installSource() }
    }

    func stop() {
        queue.sync {
            pendingChange?.cancel()
            pendingChange = nil
            source?.cancel()
            source = nil
        }
    }

    private func installSource() -> Bool {
        let fileDescriptor = open(headFile.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue)
        source.setEventHandler { [weak self] in
            self?.headChanged()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    private func headChanged() {
        let flags = source?.data ?? []
        if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
            source?.cancel()
            source = nil
            _ = installSource()
        }

        // A checkout may replace HEAD atomically and emit several vnode events.
        // Coalesce that burst into one branch lookup.
        pendingChange?.cancel()
        let change = DispatchWorkItem(block: onChange)
        pendingChange = change
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: change)
    }

    /// Normal clones keep HEAD under `.git/`; linked worktrees use a `.git`
    /// indirection file whose path is relative to the repository root.
    private static func headFile(for repository: URL) -> URL {
        let dotGit = repository.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return dotGit.appendingPathComponent("HEAD")
        }

        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
            text.hasPrefix("gitdir:")
        else {
            return dotGit.appendingPathComponent("HEAD")
        }
        let path = text.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path, relativeTo: repository)
            .standardizedFileURL
            .appendingPathComponent("HEAD")
    }
}
