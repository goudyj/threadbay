import Darwin
import Foundation

public enum AgentEventNotifier {
    public enum NotifierError: Error, LocalizedError {
        case socketCreationFailed
        case pathTooLong(String)
        case connectionFailed(String)
        case sendFailed

        public var errorDescription: String? {
            switch self {
            case .socketCreationFailed:
                return "Event socket creation failed."
            case .pathTooLong(let path):
                return "Event socket path is too long: \(path)"
            case .connectionFailed(let path):
                return "Could not connect to the event socket: \(path)"
            case .sendFailed:
                return "Could not send the agent event."
            }
        }
    }

    public static func send(
        sessionID: UUID,
        kind: String,
        payload: Data,
        socketPath: String
    ) throws {
        let payloadObject: Any = if payload.isEmpty {
            NSNull()
        } else {
            try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        }
        let event = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionID.uuidString,
            "kind": kind,
            "payload": payloadObject,
        ])
        try send(event, socketPath: socketPath)
    }

    private static func send(_ data: Data, socketPath: String) throws {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw NotifierError.socketCreationFailed }
        defer { Darwin.close(fileDescriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let maximumLength = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard pathBytes.count <= maximumLength else {
            throw NotifierError.pathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    fileDescriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw NotifierError.connectionFailed(socketPath) }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset,
                    MSG_NOSIGNAL)
                guard sent > 0 else { throw NotifierError.sendFailed }
                offset += sent
            }
        }
    }
}
