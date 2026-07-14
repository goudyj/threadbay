import Darwin
import Foundation
import ThreadBayCore

let environment = ProcessInfo.processInfo.environment
guard CommandLine.arguments.count >= 2,
    let socketPath = environment["THREADBAY_SOCK"],
    let rawSessionID = environment["THREADBAY_SESSION_ID"],
    let sessionID = UUID(uuidString: rawSessionID)
else { exit(EXIT_SUCCESS) }

let kind = CommandLine.arguments[1]
let payload: Data
if CommandLine.arguments.count >= 3 {
    payload = Data(CommandLine.arguments[2].utf8)
} else {
    payload = FileHandle.standardInput.readDataToEndOfFile()
}

try? AgentEventNotifier.send(
    sessionID: sessionID,
    kind: kind,
    payload: payload,
    socketPath: socketPath)
