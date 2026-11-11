import AppKit
import PawCore

/// A window paw manages.
final class Window {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let app: String
    /// Last frame paw set or saw (AX, top-left origin).
    var frame: CGRect
    /// Where a floating window was before its workspace was hidden.
    var floatFrame: CGRect?
    var isHidden = false
    /// Observed border bounds stay separate from the queued layout target in `frame`.
    var borderFrame: CGRect?
    var borderNeedsRefresh = true
    private var cornerRadius: CGFloat?
    private var cornerRadiusRead = false

    func invalidateCornerRadius() { cornerRadiusRead = false }

    func frameForBorder(tile: CGRect?, placeholder: Bool) -> CGRect? {
        placeholder ? tile : (borderFrame ?? tile ?? frame)
    }

    func radiusForBorder(query: (UInt32) -> CGFloat? = SkyLight.cornerRadius) -> CGFloat? {
        if !cornerRadiusRead {
            cornerRadius = query(id)
            cornerRadiusRead = true
        }
        return cornerRadius
    }

    init(id: WindowID, element: AXUIElement, pid: pid_t, app: String, frame: CGRect) {
        self.id = id
        self.element = element
        self.pid = pid
        self.app = app
        self.frame = frame
        refreshTitle()
    }

    /// Kept up to date from title-changed notifications: reading it over AX each time (for every
    /// indicator, every focus change) is slow with busy apps.
    private(set) var title = ""

    @discardableResult
    func refreshTitle() -> Bool {
        let t = element.string(kAXTitleAttribute) ?? ""
        defer { title = t }
        return t != title
    }
    var isMinimized: Bool { element.bool(kAXMinimizedAttribute) ?? false }

    /// The frame as the app has it. While a move of paw's is still on its way, `frame` (where it's
    /// going) without asking: the app would answer with where it was, or not at all if it hangs.
    func readFrame() -> CGRect? {
        if isMoving { return frame }
        let f = element.frame
        if let f {
            if f.size != frame.size { invalidateCornerRadius() }
            frame = f
            borderFrame = f
            borderNeedsRefresh = false
        }
        return f
    }

    /// Size, position, size: the second size fixes apps that clamp size to the old screen.
    /// Same size as before: just the position (one call instead of three). `settle: false` sends
    /// the size once (animation frames, where the next frame follows anyway).
    func setFrame(_ r: CGRect, settle: Bool = true) {
        let size = r.size == frame.size ? nil : r.size
        if size != nil { invalidateCornerRadius() }
        borderFrame = nil
        borderNeedsRefresh = true
        frame = r
        if AXQueue.deferring {
            if size == nil, AXQueue.viaDock(self, r.origin) { return }
            AXQueue.enqueue(self, size: size, origin: r.origin, settle: settle)
            return
        }
        // Its app hung, or still busy with earlier moves: behind those, off the main thread.
        guard AXQueue.flush(self), !AXHealth.isSlow(pid) else {
            AXQueue.enqueue(self, size: size, origin: r.origin, settle: settle)
            return
        }
        if let size { element.setSize(size) }
        element.setPosition(r.origin)
        if settle, let size { element.setSize(size) }
    }

    func setPosition(_ p: CGPoint) {
        borderFrame = nil
        borderNeedsRefresh = true
        frame.origin = p
        if AXQueue.deferring {
            if AXQueue.viaDock(self, p) { return }
            AXQueue.enqueue(self, size: nil, origin: p)
            return
        }
        guard AXQueue.flush(self), !AXHealth.isSlow(pid) else {
            AXQueue.enqueue(self, size: nil, origin: p)
            return
        }
        element.setPosition(p)
    }

    /// Moves of it handed to its app but maybe not done yet: `frame` is where it's going.
    var isMoving: Bool { AXQueue.isPending(self) }

    func focus() {
        SkyLight.focus(pid: pid, windowID: id, element: element)
    }
}

/// Window moves that don't wait for their apps: inside `run`, each move goes to its app's own
/// queue and the main thread carries on at once (an accessibility call waits for the app to
/// answer). A window keeps only its newest move: switching through workspaces quickly, those in
/// between never reach the screen. A move made outside `run` first drops what's still waiting
/// for that window, and waits for one being sent, so it lands last.
enum AXQueue {
    private struct Move {
        let window: Window
        var size: CGSize?
        var origin: CGPoint
        var settle = true
    }

    /// What a queue does with a move: the accessibility calls. Tests replace it.
    nonisolated(unsafe) static var send: (Window, CGSize?, CGPoint, Bool) -> Void = { w, size, origin, settle in
        let el = w.element
        if let size { el.setSize(size) }
        _ = el.setPosition(origin)
        if settle, let size { el.setSize(size) }
    }

    /// How long the main thread waits for a send to an app already under way before it queues
    /// its move behind it instead.
    static let flushWait: TimeInterval = 0.05

    /// Main thread only.
    private(set) static var deferring = false
    private static let lock = NSLock()
    private static var pending: [pid_t: [WindowID: Move]] = [:]
    private static var order: [pid_t: [WindowID]] = [:]
    private static var sending: Set<WindowID> = []
    private static var busy: Set<pid_t> = []
    private static var queues: [pid_t: DispatchQueue] = [:]
    /// Held per app while its queue talks to it.
    private static var appLocks: [pid_t: NSLock] = [:]

    /// Moves collected for the Dock payload during `run`, sent as one screen update at its end.
    private static var dockMoves: [(Window, CGPoint)]?

    static func run(_ body: () -> Void) {
        guard !deferring else { body(); return }
        deferring = true
        dockMoves = DockBridge.shared.isReady ? [] : nil
        body()
        deferring = false
        let moves = dockMoves ?? []
        dockMoves = nil
        // The payload gone after all (Dock restarted): the apps move them instead.
        if !moves.isEmpty, !DockBridge.shared.move(moves.map { ($0.0.id, $0.1) }) {
            run { for (w, p) in moves { enqueue(w, size: nil, origin: p) } }
        }
    }

    /// Inside `run`: a move that keeps the size goes to the Dock payload when it's there.
    static func viaDock(_ w: Window, _ p: CGPoint) -> Bool {
        guard dockMoves != nil else { return false }
        // Anything still queued for it over accessibility would land after this and undo it.
        lock.withLock {
            pending[w.pid]?[w.id] = nil
            order[w.pid]?.removeAll { $0 == w.id }
        }
        dockMoves?.append((w, p))
        return true
    }

    static func enqueue(_ w: Window, size: CGSize?, origin: CGPoint, settle: Bool = true) {
        let pid = w.pid
        lock.lock()
        var m = pending[pid]?[w.id] ?? Move(window: w, size: nil, origin: origin)
        if pending[pid]?[w.id] == nil { order[pid, default: []].append(w.id) }
        m.origin = origin
        if let size { m.size = size; m.settle = settle }
        pending[pid, default: [:]][w.id] = m
        let start = busy.insert(pid).inserted
        let q = queues[pid] ?? DispatchQueue(label: "paw.ax.\(pid)", qos: .userInteractive)
        queues[pid] = q
        let appLock = appLocks[pid] ?? NSLock()
        appLocks[pid] = appLock
        lock.unlock()
        if start { q.async { drain(pid, appLock) } }
    }

    private static func drain(_ pid: pid_t, _ appLock: NSLock) {
        while true {
            lock.lock()
            guard let ids = order[pid], !ids.isEmpty else {
                busy.remove(pid)
                lock.unlock()
                return
            }
            let moves = ids.compactMap { pending[pid]?[$0] }
            pending[pid] = nil
            order[pid] = nil
            sending.formUnion(ids)
            // Taken before letting go of `lock`: a flush either finds a move pending or waits.
            appLock.lock()
            lock.unlock()
            for m in moves { send(m.window, m.size, m.origin, m.settle) }
            lock.lock()
            sending.subtract(ids)
            lock.unlock()
            appLock.unlock()
        }
    }

    static func isPending(_ w: Window) -> Bool {
        lock.withLock { pending[w.pid]?[w.id] != nil || sending.contains(w.id) }
    }

    /// Main thread, before a move made outside `run`: true when nothing of `w`'s is under way
    /// any more, so the move can go now and land last. False when a send to its app is still
    /// going after `flushWait` (the app is slow or hung): queue the move behind it instead.
    @discardableResult
    static func flush(_ w: Window, wait: TimeInterval = flushWait) -> Bool {
        lock.lock()
        guard pending[w.pid]?[w.id] != nil || sending.contains(w.id) || busy.contains(w.pid) else { lock.unlock(); return true }
        // Its app's queue is still working: a move sent now could land before older ones.
        if pending[w.pid]?[w.id] == nil, !sending.contains(w.id) {
            lock.unlock()
            return false
        }
        let appLock = appLocks[w.pid]
        lock.unlock()
        guard let appLock else { return true }
        guard appLock.lock(before: Date(timeIntervalSinceNow: wait)) else { return false }
        appLock.unlock()
        // Done sending: nothing left that could land after the new move.
        return lock.withLock { pending[w.pid]?[w.id] == nil && !busy.contains(w.pid) }
    }

    /// The app quit: its queue and lock go.
    static func forget(_ pid: pid_t) {
        lock.withLock {
            guard !busy.contains(pid) else { return }
            pending[pid] = nil
            order[pid] = nil
            queues[pid] = nil
            appLocks[pid] = nil
        }
    }

    /// For tests: waits until every queue is idle.
    static func waitIdle(timeout: TimeInterval = 2) -> Bool {
        let end = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if lock.withLock({ busy.isEmpty }) { return true }
            usleep(1000)
        }
        return false
    }
}
