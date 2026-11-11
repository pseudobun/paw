import Darwin
import Foundation

/// `paw subscribe`: events as JSON lines over paw's socket, one long-lived connection per
/// subscriber instead of a shell command per event. Every line is
/// `{"seq":N,"ts":…,"event":"…","data":{…}}`; `seq` counts up per subscriber, so a gap means
/// lines were lost. The first line is a `snapshot` of everything `paw query` knows, so a client
/// never has to ask separately (and can't race an event).
final class EventBus {
    static let shared = EventBus()
    static let names = ["snapshot", "workspaceChanged", "windowFocused", "windowsChanged", "layoutChanged", "zoomChanged",
                        "modeChanged", "displaysChanged", "setupChanged", "configReloaded"]

    private final class Subscriber {
        let fd: Int32
        let events: Set<String>?
        let queue = DispatchQueue(label: "paw.subscriber")
        var seq = 0
        var pending = 0
        var dead = false

        init(fd: Int32, events: Set<String>?) {
            self.fd = fd
            self.events = events
        }
    }

    private let lock = NSLock()
    private var subscribers: [Subscriber] = []
    /// A client further behind than this many lines is dropped (it reconnects and gets a new
    /// snapshot) instead of holding paw up.
    private let maxPending = 512
    /// Each subscriber costs a descriptor and a write per event; past this many, new ones are
    /// turned away so a runaway script can't pile them up on the main thread.
    static let maxSubscribers = 64

    var hasSubscribers: Bool { lock.withLock { !subscribers.isEmpty } }

    /// Takes over `fd` (a connection that asked `subscribe [events]`) and sends `snapshot` first.
    func add(fd: Int32, request: String, snapshot: [String: Any]) {
        let words = request.split(separator: " ").dropFirst().flatMap { $0.split(separator: ",") }.map(String.init)
        let events = words.isEmpty ? nil : Set(words)
        // Writes may block a little; a stuck reader is dropped after 2 s.
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let s = Subscriber(fd: fd, events: events)
        let accepted = lock.withLock { () -> Bool in
            guard subscribers.count < Self.maxSubscribers else { return false }
            subscribers.append(s)
            return true
        }
        guard accepted else {
            Log.app.error("ipc: \(Self.maxSubscribers) subscribers already; refusing another")
            DispatchQueue.global().async {
                _ = IPC.writeAll(fd, Data("{\"error\":\"too many subscribers\"}\n".utf8))
                close(fd)
            }
            return
        }
        guard let body = Self.encode(snapshot) else { return }
        send(s, "snapshot", body)
    }

    /// Sends an event to everyone who wants it. Main thread.
    func publish(_ event: String, _ data: [String: Any]) {
        let list = lock.withLock { subscribers }.filter { s in s.events.map { $0.contains(event) || event == "snapshot" } ?? true }
        guard !list.isEmpty, let body = Self.encode(data) else { return }
        for s in list { send(s, event, body) }
    }

    /// `data` as JSON, once per event however many subscribers there are.
    private static func encode(_ data: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
    }

    /// Writes `{"data":…,"event":…,"seq":…,"ts":…}` (keys sorted, as before) around the
    /// already-encoded `body`.
    private func send(_ s: Subscriber, _ event: String, _ body: Data) {
        guard !s.dead else { return }
        s.seq += 1
        guard let name = try? JSONSerialization.data(withJSONObject: event, options: [.fragmentsAllowed]) else { return }
        var out = Data("{\"data\":".utf8)
        out.append(body)
        out.append(Data(",\"event\":".utf8))
        out.append(name)
        out.append(Data(",\"seq\":\(s.seq),\"ts\":\(Date().timeIntervalSince1970)}\n".utf8))
        s.pending += 1
        if s.pending > maxPending {
            Log.app.error("subscriber \(s.fd) fell \(s.pending) events behind; dropping it")
            drop(s)
            return
        }
        s.queue.async { [weak self] in
            let ok = IPC.writeAll(s.fd, out)
            DispatchQueue.main.async {
                s.pending -= 1
                if !ok { self?.drop(s) }
            }
        }
    }

    private func drop(_ s: Subscriber) {
        guard !s.dead else { return }
        s.dead = true
        lock.withLock { subscribers.removeAll { $0 === s } }
        s.queue.async { close(s.fd) }
    }

    func closeAll() {
        for s in lock.withLock({ subscribers }) { drop(s) }
    }
}
