import Darwin
import Foundation

/// Minimal Unix-domain-socket server for notifier events (decision n°8). One
/// client connection carries one event: the bytes are read to EOF and handed
/// to `handler` on a background queue.
public final class EventSocketServer: @unchecked Sendable {
    public enum SocketError: Error, LocalizedError {
        case creationFailed
        case pathTooLong(String)
        case bindFailed(String)

        public var errorDescription: String? {
            switch self {
            case .creationFailed: return "Event socket creation failed."
            case .pathTooLong(let path): return "Event socket path is too long: \(path)"
            case .bindFailed(let path): return "Event socket bind/listen failed: \(path)"
            }
        }
    }

    private let path: String
    private let handler: @Sendable (Data) -> Void
    private let acceptQueue = DispatchQueue(label: "threadbay.events.accept")
    private let readQueue = DispatchQueue(
        label: "threadbay.events.read", attributes: .concurrent)
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
        guard fd >= 0 else { throw SocketError.creationFailed }

        let bound: Int32
        do {
            bound = try withUnixSocketAddress(path, pathTooLong: SocketError.pathTooLong) {
                Darwin.bind(fd, $0, $1)
            }
        } catch {
            close(fd)
            throw error
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SocketError.bindFailed(path)
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
