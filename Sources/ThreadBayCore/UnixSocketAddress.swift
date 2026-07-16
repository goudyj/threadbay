import Darwin
import Foundation

/// Builds a `sockaddr_un` for `path` and hands it to `body` as the generic
/// `sockaddr` pointer expected by `bind`/`connect`. `pathTooLong` supplies the
/// caller's own error when the path exceeds `sun_path`.
func withUnixSocketAddress(
    _ path: String,
    pathTooLong: (String) -> Error,
    _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32
) throws -> Int32 {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let maximumLength = MemoryLayout.size(ofValue: address.sun_path) - 1
    guard pathBytes.count <= maximumLength else { throw pathTooLong(path) }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: pathBytes)
    }
    return withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}
