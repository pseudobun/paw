import Darwin
import Foundation

/// CLI ↔ app over a Unix socket that only this user can reach: the directory is 0700, the socket
/// 0600, and the app checks every peer's uid. A request is one command (`run focus west`, `query`…)
/// sent until EOF; the reply is one JSON object, then the app closes the connection.
enum IPC {
    static let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: AppPaths.bundleID, directoryHint: .isDirectory)
    static var socketPath: String { dir.appending(path: "paw.sock").path }

    static let maxRequest = 64 * 1024
    static let maxReply = 16 * 1024 * 1024

    // MARK: - Client

    enum ClientError: Error { case notRunning, failed(String) }

    /// Sends `command` and returns the app's reply.
    static func send(_ command: String, timeout: TimeInterval) -> Result<[String: Any], ClientError> {
        guard FileManager.default.fileExists(atPath: socketPath) else { return .failure(.notRunning) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(.failed("socket: \(String(cString: strerror(errno)))")) }
        defer { close(fd) }
        configure(fd, timeout: timeout)
        guard var addr = address(socketPath) else { return .failure(.failed("socket path too long")) }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            return errno == ECONNREFUSED || errno == ENOENT ? .failure(.notRunning)
                : .failure(.failed("connect: \(String(cString: strerror(errno)))"))
        }
        guard writeAll(fd, Data(command.utf8)) else { return .failure(.failed("write: \(String(cString: strerror(errno)))")) }
        shutdown(fd, SHUT_WR)
        guard let data = readAll(fd, limit: maxReply), !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.failed("paw did not answer"))
        }
        return .success(obj)
    }

    // MARK: - Server

    final class Server {
        private let handler: (String) -> [String: Any]
        private var listener: Int32 = -1

        /// `handler` runs on the main thread with the request text and returns the reply.
        init(handler: @escaping (String) -> [String: Any]) { self.handler = handler }

        func start() throws {
            try IPC.prepareDirectory()
            let path = IPC.socketPath
            guard var addr = IPC.address(path) else { throw IPCError("socket path too long: \(path)") }
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw IPCError("socket: \(String(cString: strerror(errno)))") }
            // Created 0600 from the start: no window where another user could connect.
            let old = umask(0o177)
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            umask(old)
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
                let message = String(cString: strerror(errno))
                close(fd)
                throw IPCError("bind \(path): \(message)")
            }
            listener = fd
            let thread = Thread { [weak self] in self?.acceptLoop(fd) }
            thread.name = "paw.ipc"
            thread.start()
        }

        func stop() {
            guard listener >= 0 else { return }
            close(listener)
            listener = -1
            unlink(IPC.socketPath)
        }

        private func acceptLoop(_ fd: Int32) {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR || errno == ECONNABORTED { continue }
                    return // closed by stop()
                }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(client) }
            }
        }

        private func serve(_ fd: Int32) {
            defer { close(fd) }
            IPC.configure(fd, timeout: 5)
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                Log.app.error("ipc: refused a peer of uid \(uid)")
                return
            }
            guard let data = IPC.readAll(fd, limit: IPC.maxRequest) else {
                Log.app.error("ipc: unreadable or oversized request")
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let reply = DispatchQueue.main.sync { handler(text) }
            let out = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data("{}".utf8)
            _ = IPC.writeAll(fd, out)
        }
    }

    struct IPCError: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    // MARK: - Helpers

    /// The socket's directory: ours, a real directory, 0700.
    static func prepareDirectory() throws {
        let path = dir.path
        if mkdir(path, 0o700) != 0, errno != EEXIST { throw IPCError("mkdir \(path): \(String(cString: strerror(errno)))") }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else {
            throw IPCError("\(path) is not a directory owned by this user")
        }
        if st.st_mode & 0o777 != 0o700, chmod(path, 0o700) != 0 {
            throw IPCError("chmod \(path): \(String(cString: strerror(errno)))")
        }
    }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        return addr
    }

    static func configure(_ fd: Int32, timeout: TimeInterval) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
    }

    /// Reads until EOF; nil on error, timeout or more than `limit` bytes.
    static func readAll(_ fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0, errno == EINTR { continue }
            guard n >= 0 else { return nil }
            if n == 0 { return data }
            data.append(contentsOf: buffer[0..<n])
            if data.count > limit { return nil }
        }
    }
}
