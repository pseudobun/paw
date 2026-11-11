import Foundation

/// A thread of its own for paw's event taps (key bindings, mouse gestures). Every key press,
/// scroll tick and trackpad event in the session passes through a tap before it reaches its app;
/// on the main thread they would wait whenever paw is busy laying out windows. Here they're
/// answered at once, and only the commands they trigger go to the main thread.
final class EventTapThread: Thread {
    static let shared = EventTapThread()

    private let ready = DispatchSemaphore(value: 0)
    private var loop: CFRunLoop?

    private override init() {
        super.init()
        name = "paw.eventtaps"
        qualityOfService = .userInteractive
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A run loop with no sources returns at once: a port keeps it alive until taps arrive.
        let keepAlive = CFMachPortCreate(nil, nil, nil, nil)
        if let source = CFMachPortCreateRunLoopSource(nil, keepAlive, 0) {
            CFRunLoopAddSource(loop, source, .commonModes)
        }
        ready.signal()
        while !isCancelled { CFRunLoopRun() }
    }

    /// The thread's run loop, started on first use.
    var runLoop: CFRunLoop {
        if loop == nil {
            if !isExecuting { start() }
            ready.wait()
            ready.signal()
        }
        return loop!
    }

    func add(_ source: CFRunLoopSource) {
        let l = runLoop
        CFRunLoopAddSource(l, source, .commonModes)
        CFRunLoopWakeUp(l)
    }

    func remove(_ source: CFRunLoopSource) {
        let l = runLoop
        CFRunLoopRemoveSource(l, source, .commonModes)
        CFRunLoopWakeUp(l)
    }

    /// True on the tap thread (for tests and assertions).
    static var isCurrent: Bool { CFRunLoopGetCurrent() === shared.loop }
}
