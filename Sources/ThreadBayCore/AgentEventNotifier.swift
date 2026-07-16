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

        let connected = try withUnixSocketAddress(
            socketPath, pathTooLong: NotifierError.pathTooLong
        ) {
            Darwin.connect(fileDescriptor, $0, $1)
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
