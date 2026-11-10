import Darwin
import Foundation

/// `paw subscribe`: events as JSON lines over paw's socket, one long-lived connection per
/// subscriber instead of a shell command per event. Every line is
/// `{"seq":N,"ts":…,"event":"…","data":{…}}`; `seq` counts up per subscriber, so a gap means
/// lines were lost. The first line is a `snapshot` of everything `paw query` knows, so a client
/// never has to ask separately (and can't race an event).
final class EventBus {
    static let shared = EventBus()
    static let names = ["snapshot", "workspaceChanged", "windowFocused", "windowsChanged", "layoutChanged",
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

    var hasSubscribers: Bool { lock.withLock { !subscribers.isEmpty } }

    /// Takes over `fd` (a connection that asked `subscribe [events]`) and sends `snapshot` first.
    func add(fd: Int32, request: String, snapshot: [String: Any]) {
        let words = request.split(separator: " ").dropFirst().flatMap { $0.split(separator: ",") }.map(String.init)
        let events = words.isEmpty ? nil : Set(words)
        // Writes may block a little; a stuck reader is dropped after 2 s.
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let s = Subscriber(fd: fd, events: events)
        lock.withLock { subscribers.append(s) }
        send(s, "snapshot", snapshot)
    }

    /// Sends an event to everyone who wants it. Main thread.
    func publish(_ event: String, _ data: [String: Any]) {
        let list = lock.withLock { subscribers }
        for s in list where s.events.map({ $0.contains(event) || event == "snapshot" }) ?? true {
            send(s, event, data)
        }
    }

    private func send(_ s: Subscriber, _ event: String, _ data: [String: Any]) {
        guard !s.dead else { return }
        s.seq += 1
        let line: [String: Any] = ["seq": s.seq, "ts": Date().timeIntervalSince1970, "event": event, "data": data]
        guard var out = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        out.append(0x0a)
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
