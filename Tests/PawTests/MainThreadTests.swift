import AppKit
import PawCore
import Testing
@testable import paw

/// The main thread never waits on a slow or hung app: moves go to each app's own queue, calls to
/// an app that timed out fail at once, and the queue keeps only each window's newest move.
/// (AXQueue and AXHealth are process-wide, hence serialized.)
@MainActor
@Suite(.serialized)
struct MainThreadTests {
    /// A window of an app that isn't there: its accessibility calls fail at once.
    private func window(_ id: WindowID, pid: pid_t = 99_991) -> Window {
        Window(id: id, element: AXUIElementCreateApplication(pid), pid: pid, app: "Fake", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    /// Replaces the queue's accessibility calls for the test: each move is recorded, and a move
    /// to a "hung" window blocks until `release` is signalled.
    private final class FakeApp: @unchecked Sendable {
        let lock = NSLock()
        var sent: [(WindowID, CGSize?, CGPoint)] = []
        let release = DispatchSemaphore(value: 0)
        private var _hung: Set<WindowID> = []
        var hung: Set<WindowID> {
            get { lock.withLock { _hung } }
            set { lock.withLock { _hung = newValue } }
        }

        func install() {
            AXQueue.send = { [self] w, size, origin, _ in
                let block = hung.contains(w.id)
                if block { release.wait() }
                lock.withLock { sent.append((w.id, size, origin)) }
            }
        }

        var moves: [(WindowID, CGSize?, CGPoint)] { lock.withLock { sent } }
    }

    private func restore() {
        AXQueue.send = { w, size, origin, settle in
            let el = w.element
            if let size { el.setSize(size) }
            _ = el.setPosition(origin)
            if settle, let size { el.setSize(size) }
        }
        AXHealth.reset()
    }

    // MARK: AXHealth

    @Test func aTimedOutAppFailsAtOnceOnTheMainThreadOnly() {
        defer { restore() }
        let t = 100.0
        AXHealth.clock = { t }
        defer { AXHealth.clock = { CACurrentMediaTime() } }
        let pid: pid_t = 4242
        #expect(!AXHealth.isSlow(pid))
        AXHealth.record(pid, .cannotComplete, elapsed: 0.5)
        #expect(AXHealth.isSlow(pid))

        var calls = 0
        let onMain = AXHealth.call(pid: pid, onMain: true) { calls += 1; return .success }
        #expect(onMain == .cannotComplete)
        #expect(calls == 0, "the main thread doesn't wait on it again")
        let off = AXHealth.call(pid: pid, onMain: false) { calls += 1; return .success }
        #expect(off == .success)
        #expect(calls == 1, "its own queue still talks to it")
        #expect(!AXHealth.isSlow(pid), "an answer clears it")
    }

    @Test func slowCallsBackOffDoublingUpToThirtySeconds() {
        defer { restore() }
        var t = 1000.0
        AXHealth.clock = { t }
        defer { AXHealth.clock = { CACurrentMediaTime() } }
        let pid: pid_t = 4243
        var lengths: [Double] = []
        for _ in 0..<7 {
            AXHealth.record(pid, .success, elapsed: AXHealth.slowCall + 0.01)
            // How long it stays marked: step forward until it isn't.
            var waited = 0.0
            while AXHealth.isSlow(pid) { t += 0.5; waited += 0.5 }
            lengths.append(waited)
        }
        #expect(lengths == [2, 4, 8, 16, 30, 30, 30])
        AXHealth.record(pid, .success, elapsed: 0.01)
        AXHealth.record(pid, .cannotComplete, elapsed: 0.5)
        var waited = 0.0
        while AXHealth.isSlow(pid) { t += 0.5; waited += 0.5 }
        #expect(waited == 2, "a fast answer starts the backoff over")
    }

    @Test func fastCallsNeverMarkAnApp() {
        defer { restore() }
        for _ in 0..<100 { AXHealth.record(4244, .success, elapsed: 0.01) }
        AXHealth.record(4244, .attributeUnsupported, elapsed: 0.01)
        #expect(!AXHealth.isSlow(4244))
        AXHealth.record(4244, .cannotComplete, elapsed: 0.5)
        AXHealth.forget(4244)
        #expect(!AXHealth.isSlow(4244), "an app that quit is forgotten")
    }

    // MARK: AXQueue

    @Test func movesInsideRunReturnAtOnceWhileTheAppHangs() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let w = window(1)
        app.hung = [1]
        let t0 = CACurrentMediaTime()
        AXQueue.run { w.setFrame(CGRect(x: 10, y: 10, width: 200, height: 200)) }
        for i in 0..<50 {
            AXQueue.run { w.setPosition(CGPoint(x: Double(i), y: 0)) }
        }
        let elapsed = CACurrentMediaTime() - t0
        #expect(elapsed < 0.4, "51 moves to a hung app took \(elapsed) s on the main thread")
        #expect(w.isMoving)
        #expect(w.readFrame() == CGRect(x: 49, y: 0, width: 200, height: 200), "where it's going, without asking the app")
        app.hung = []
        app.release.signal()
        #expect(AXQueue.waitIdle())
        // At most the first move (if it was already being sent) and the newest of the 50 after it.
        let moves = app.moves
        #expect(moves.count <= 2)
        #expect(moves.last?.2 == CGPoint(x: 49, y: 0))
        #expect(!w.isMoving)
    }

    @Test func aMoveOutsideRunQueuesBehindAHungSendInsteadOfWaiting() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let w = window(2)
        app.hung = [2]
        AXQueue.run { w.setPosition(CGPoint(x: 1, y: 1)) }
        // The queue is now stuck sending that move.
        usleep(20_000)
        let t0 = CACurrentMediaTime()
        w.setFrame(CGRect(x: 300, y: 300, width: 120, height: 80))
        let elapsed = CACurrentMediaTime() - t0
        #expect(elapsed < AXQueue.flushWait + 0.4, "waited \(elapsed) s for a hung app (it never answers)")
        #expect(w.isMoving)
        app.hung = []
        app.release.signal()
        #expect(AXQueue.waitIdle())
        #expect(app.moves.last?.2 == CGPoint(x: 300, y: 300), "the newer move lands last")
        #expect(app.moves.last?.1 == CGSize(width: 120, height: 80))
    }

    @Test func aMoveOutsideRunGoesStraightToAnIdleApp() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let w = window(3)
        // (Making it asked the missing app for its title, which may have marked it.)
        AXHealth.reset()
        #expect(AXQueue.flush(w))
        w.setPosition(CGPoint(x: 5, y: 6))
        // Sent on the main thread by the element itself (the fake app has none), not queued.
        #expect(!w.isMoving)
        #expect(app.moves.isEmpty)
    }

    @Test func aMarkedSlowAppGetsItsMovesQueued() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let w = window(4, pid: 99_992)
        AXHealth.record(99_992, .cannotComplete, elapsed: 0.5)
        w.setFrame(CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(AXQueue.waitIdle())
        #expect(app.moves.count == 1, "queued for its own thread, not tried on main")
    }

    @Test func eachWindowKeepsOnlyItsNewestMoveAndAppsDontWaitOnEachOther() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let stuck = window(10, pid: 99_993)
        let fine = window(11, pid: 99_994)
        app.hung = [10]
        AXQueue.run {
            stuck.setPosition(CGPoint(x: 1, y: 0))
            fine.setPosition(CGPoint(x: 2, y: 0))
        }
        // The other app's move goes out while the first app hangs.
        let deadline = Date(timeIntervalSinceNow: 1)
        while !app.moves.contains(where: { $0.0 == 11 }), Date() < deadline { usleep(1000) }
        #expect(app.moves.map(\.0) == [11])
        app.release.signal()
        #expect(AXQueue.waitIdle())
        #expect(Set(app.moves.map(\.0)) == [10, 11])
    }

    @Test func forgettingAnAppDropsItsQueue() {
        defer { restore() }
        let app = FakeApp()
        app.install()
        let w = window(20, pid: 99_995)
        AXQueue.run { w.setPosition(.zero) }
        #expect(AXQueue.waitIdle())
        AXQueue.forget(99_995)
        AXQueue.run { w.setPosition(CGPoint(x: 1, y: 1)) }
        #expect(AXQueue.waitIdle())
        #expect(app.moves.count == 2, "a new queue for it if it shows up again")
    }

    // MARK: Focus

    @Test func onlyTheNewestFocusRequestGoes() {
        let t = FocusTicket()
        let a = t.issue(), b = t.issue()
        #expect(!t.isLatest(a))
        #expect(t.isLatest(b))
        let q = DispatchQueue(label: "test", attributes: .concurrent)
        q.sync { DispatchQueue.concurrentPerform(iterations: 1000) { _ in _ = t.issue() } }
        #expect(t.isLatest(b + 1000))
    }

    @Test func titleRetriesBackOffToAMinute() {
        var i: TimeInterval?
        var seen: [TimeInterval] = []
        for _ in 0..<8 { i = WindowManager.nextBackoff(i); seen.append(i!) }
        #expect(seen == [1, 2, 4, 8, 16, 32, 60, 60])
    }

    // MARK: Accessibility prompt

    @Test func theAccessibilityPromptComesOncePerBuildAndNeverWhenGranted() throws {
        let defaults = try #require(UserDefaults(suiteName: "paw.tests.\(UUID())"))
        var asked = 0
        AppDelegate.askForTrustOnce(defaults: defaults, build: "1", isTrusted: { true }, request: { asked += 1 })
        #expect(asked == 0, "granted: never")
        AppDelegate.askForTrustOnce(defaults: defaults, build: "1", isTrusted: { false }, request: { asked += 1 })
        AppDelegate.askForTrustOnce(defaults: defaults, build: "1", isTrusted: { false }, request: { asked += 1 })
        #expect(asked == 1, "once per build")
        AppDelegate.askForTrustOnce(defaults: defaults, build: "2", isTrusted: { false }, request: { asked += 1 })
        #expect(asked == 2, "a new build may ask again")
    }
}
