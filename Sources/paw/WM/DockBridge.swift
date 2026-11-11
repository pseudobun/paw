import Darwin
import Foundation
import PawCore

/// Window moves through paw's payload inside Dock.app (see Sources/PawDock): the window server
/// moves a window at once, instead of asking its app over accessibility and waiting for the app
/// to get round to it. Needs SIP's debugging restrictions off and the payload loaded
/// (`paw dock load`); without it every move goes over accessibility as before.
final class DockBridge {
    static let shared = DockBridge()

    enum State: String {
        /// The setting says accessibility.
        case off
        /// SIP doesn't allow loading into Dock.
        case sipEnabled
        /// Allowed, but the payload isn't loaded (Dock restarted, or never loaded).
        case notLoaded
        case ready
    }

    private var fd: Int32 = -1
    /// What the payload in Dock said it is, on the last hello.
    private(set) var loadedVersion: String?
    private var lastTry = Date.distantPast
    /// From config: "auto" uses the payload when it's there, "accessibility" never does.
    var enabled = true

    /// In the user's own temporary directory (0700), where the payload listens: not /tmp, where
    /// another user could take the name.
    static var socketPath: String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, buf.count)
        let dir = n > 0 && n <= buf.count ? String(cString: buf) : NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("paw-dock.sock")
    }

    static let dockPath = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"

    /// The other end is Dock, running as this user: anything else on the socket is not the payload.
    private static func peerIsDock(_ s: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(s, &uid, &gid) == 0, uid == getuid() else { return false }
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(s, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == 0, pid > 0 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        return String(cString: path) == dockPath
    }

    /// SIP's "allow task_for_pid" (CSR_ALLOW_TASK_FOR_PID): what `csrutil enable --without debug` turns on.
    static let sipAllowsLoading: Bool = {
        typealias Fn = @convention(c) (UnsafeMutablePointer<UInt32>) -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csr_get_active_config") else { return false }
        var config: UInt32 = 0
        guard unsafeBitCast(sym, to: Fn.self)(&config) == 0 else { return false }
        return config & 0x4 != 0
    }()

    var state: State {
        guard enabled else { return .off }
        guard Self.sipAllowsLoading else { return .sipEnabled }
        return connect() ? .ready : .notLoaded
    }

    var isReady: Bool { enabled && Self.sipAllowsLoading && connect() }

    /// For `paw status` and settings.
    var statusLine: String {
        switch state {
        case .off: return "off: windows move over accessibility"
        case .sipEnabled: return "SIP is on: windows move over accessibility (README, Faster workspace switching)"
        case .notLoaded: return "Dock helper not loaded: sudo paw dock install"
        case .ready:
            guard let advice = Self.advice(bundled: Self.bundledVersion, installed: Self.installedVersion, loaded: loadedVersion)
            else { return "through the Dock helper" }
            return "through the Dock helper (\(advice))"
        }
    }

    // MARK: Versions

    /// The helper's version is a hash of its source (scripts/bundle.sh): the one in this paw.app,
    /// the one `paw dock install` copied out, and the one Dock runs can each differ.
    static var bundledVersion: String? {
        readVersion(AppPaths.appBundle.bundleURL.appending(path: "Contents/Resources/dock/VERSION").path)
    }

    static var installedVersion: String? { readVersion(DockCLI.dir + "/VERSION") }

    static func readVersion(_ path: String) -> String? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// "paw-dock <version>\n" → the version.
    static func helloVersion(_ reply: String) -> String? {
        guard reply.hasPrefix("paw-dock ") else { return nil }
        let v = reply.dropFirst("paw-dock ".count).prefix { $0 != "\n" && $0 != "\0" }
        return v.isEmpty ? nil : String(v)
    }

    /// What to do when the helper in Dock isn't this paw's, or nil when it is (or this build has
    /// no version to compare: a build without scripts/bundle.sh).
    static func advice(bundled: String?, installed: String?, loaded: String?) -> String? {
        guard let bundled else { return nil }
        if installed != bundled { return "outdated: sudo paw dock install" }
        if let loaded, loaded != bundled { return "Dock still runs the old one: killall Dock" }
        return nil
    }

    /// Whether the payload answers (for `paw dock status`, from the CLI).
    func ping() -> Bool { Self.sipAllowsLoading && connect(force: true) }

    /// Moves windows (AX coordinates) in one screen update. False when the payload isn't there.
    @discardableResult
    func move(_ moves: [(WindowID, CGPoint)]) -> Bool {
        guard !moves.isEmpty else { return true }
        var body = Data([0x02])
        append(&body, UInt32(moves.count))
        for (id, p) in moves {
            append(&body, UInt32(id))
            append(&body, Double(p.x))
            append(&body, Double(p.y))
        }
        return send(body)
    }

    /// Brings windows to the front, in order (the last ends up on top).
    @discardableResult
    func order(_ ids: [WindowID]) -> Bool {
        guard !ids.isEmpty else { return true }
        var body = Data([0x03])
        append(&body, UInt32(ids.count))
        for id in ids { append(&body, UInt32(id)) }
        return send(body)
    }

    private func append<T>(_ d: inout Data, _ v: T) {
        withUnsafeBytes(of: v) { d.append(contentsOf: $0) }
    }

    private func send(_ body: Data) -> Bool {
        guard connect() else { return false }
        var msg = Data()
        append(&msg, UInt32(body.count))
        msg.append(body)
        if IPC.writeAll(fd, msg) { return true }
        // Dock restarted (the payload went with it): try once more on a new connection.
        close(fd); fd = -1
        guard connect(force: true), IPC.writeAll(fd, msg) else { return false }
        return true
    }

    /// An open, greeted connection to the payload. Retries at most every 2 s when it isn't there.
    private func connect(force: Bool = false) -> Bool {
        if fd >= 0 { return true }
        guard Self.sipAllowsLoading, force || Date().timeIntervalSince(lastTry) > 2 else { return false }
        lastTry = Date()
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Self.socketPath
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            path.utf8CString.withUnsafeBytes { src in p.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(p.count - 1))) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, Self.peerIsDock(s) else { close(s); return false }
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var nosig: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        // Hello: the payload answers with its version.
        var hello = Data()
        withUnsafeBytes(of: UInt32(1)) { hello.append(contentsOf: $0) }
        hello.append(0x01)
        var reply = [UInt8](repeating: 0, count: 64)
        guard IPC.writeAll(s, hello), read(s, &reply, reply.count) > 0,
              let version = Self.helloVersion(String(decoding: reply, as: UTF8.self)) else { close(s); return false }
        fd = s
        loadedVersion = version
        Log.app.notice("dock: payload connected")
        return true
    }
}
