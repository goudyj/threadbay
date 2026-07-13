import Darwin
import Foundation

/// Minimal Unix-domain-socket server for notifier events (decision n°8). One
/// client connection carries one event: the bytes are read to EOF and handed
/// to `handler` on a background queue.
public final class EventSocketServer: @unchecked Sendable {
    public enum SocketError: Error, LocalizedError {
        case failed(String)
        public var errorDescription: String? {
            if case .failed(let step) = self { return "Socket d'événements : échec \(step)." }
            return nil
        }
    }

    private let path: String
    private let handler: @Sendable (Data) -> Void
    private let acceptQueue = DispatchQueue(label: "orchestrate.events.accept")
    private let readQueue = DispatchQueue(
        label: "orchestrate.events.read", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(path: String, handler: @escaping @Sendable (Data) -> Void) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.failed("socket()") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let bytes = Array(path.utf8)
        guard bytes.count <= maxLen else {
            close(fd)
            throw SocketError.failed("chemin trop long (\(path))")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            dst.copyBytes(from: bytes)
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SocketError.failed("bind/listen sur \(path)")
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        unlink(path)
    }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        let handler = handler
        readQueue.async {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(client, &buffer, buffer.count)
                guard n > 0 else { break }
                data.append(buffer, count: n)
            }
            close(client)
            if !data.isEmpty { handler(data) }
        }
    }
}
