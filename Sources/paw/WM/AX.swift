import AppKit
import ApplicationServices
import QuartzCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()

    func value(_ attr: String) -> AnyObject? {
        var v: CFTypeRef?
        let ok = AXHealth.call(self) { AXUIElementCopyAttributeValue(self, attr as CFString, &v) }
        return ok == .success ? v : nil
    }

    func string(_ attr: String) -> String? { value(attr) as? String }
    func bool(_ attr: String) -> Bool? { (value(attr) as? NSNumber)?.boolValue }

    func element(_ attr: String) -> AXUIElement? {
        guard let v = value(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func elements(_ attr: String) -> [AXUIElement] {
        (value(attr) as? [AnyObject] ?? []).compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    @discardableResult
    func set(_ attr: String, _ value: CFTypeRef) -> Bool {
        AXHealth.call(self) { AXUIElementSetAttributeValue(self, attr as CFString, value) } == .success
    }

    func isSettable(_ attr: String) -> Bool {
        var b: DarwinBoolean = false
        return AXHealth.call(self) { AXUIElementIsAttributeSettable(self, attr as CFString, &b) } == .success && b.boolValue
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    var position: CGPoint? {
        guard let v = value(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = value(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    func setPosition(_ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(kAXPositionAttribute, v)
    }

    @discardableResult
    func setSize(_ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return set(kAXSizeAttribute, v)
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXHealth.call(self) { AXUIElementPerformAction(self, action as CFString) } == .success
    }
}

/// Apps that stopped answering accessibility calls. A call to one that times out (the app is
/// hung, or busy for longer than the messaging timeout) marks it slow; while it is, calls to it
/// from the main thread fail at once instead of waiting out the timeout again, so one hung app
/// can't hold up paw. Moves still reach it from its own queue (AXQueue), off the main thread.
/// Each timeout in a row doubles how long it stays marked, up to 30 s; an answer clears it.
enum AXHealth {
    /// A call slower than this counts as a timeout even when it got through.
    static let slowCall: Double = 0.25
    static let firstBackoff: Double = 2
    static let maxBackoff: Double = 30

    private struct State {
        var until: Double
        var strikes: Int
    }

    private static let lock = NSLock()
    private static var slow: [pid_t: State] = [:]
    /// Seconds, monotonic. Tests replace it.
    nonisolated(unsafe) static var clock: () -> Double = { CACurrentMediaTime() }

    static func isSlow(_ pid: pid_t) -> Bool {
        let t = clock()
        return lock.withLock { (slow[pid]?.until ?? 0) > t }
    }

    /// Runs one accessibility call to `element`'s app, or fails it at once (cannotComplete) when
    /// that app is marked slow and this is the main thread.
    static func call(_ element: AXUIElement, onMain: Bool = Thread.isMainThread, _ body: () -> AXError) -> AXError {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return body() }
        return call(pid: pid, onMain: onMain, body)
    }

    static func call(pid: pid_t, onMain: Bool, _ body: () -> AXError) -> AXError {
        if onMain, isSlow(pid) { return .cannotComplete }
        let t0 = clock()
        let err = body()
        record(pid, err, elapsed: clock() - t0)
        return err
    }

    static func record(_ pid: pid_t, _ err: AXError, elapsed: Double) {
        let timedOut = err == .cannotComplete || elapsed >= slowCall
        let t = clock()
        lock.withLock {
            if timedOut {
                let strikes = (slow[pid]?.strikes ?? 0) + 1
                let backoff = min(maxBackoff, firstBackoff * pow(2, Double(strikes - 1)))
                slow[pid] = State(until: t + backoff, strikes: strikes)
            } else if slow[pid] != nil {
                slow[pid] = nil
            }
        }
    }

    /// The app quit.
    static func forget(_ pid: pid_t) { _ = lock.withLock { slow.removeValue(forKey: pid) } }

    static func reset() { lock.withLock { slow = [:] } }
}

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
