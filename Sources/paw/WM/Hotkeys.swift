import AppKit
import PawCore

/// Global key bindings through a session event tap (needs Accessibility, like the rest of paw).
/// Unlike Carbon hotkeys it tells left from right modifiers, so "ralt+1" works.
///
/// The tap runs on `EventTapThread`, not the main thread: a key press is matched there at once,
/// and only the commands go to the main thread. The tables are swapped under `lock`.
final class Hotkeys {
    private let lock = NSLock()
    private var byKey: [UInt16: [(KeySpec, [Command])]] = [:]
    private var modeKeys: [String: [UInt16: [(KeySpec, [Command])]]] = [:]
    private var _mode: String?
    /// A held key's repeat already waiting for the main thread: further repeats are dropped
    /// until it has run, so holding a key never piles up work that goes on after it's let go.
    private var repeatPending = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var run: (([Command]) -> Void)?
    private(set) var problems: [String] = []

    /// The mode whose keys come first; nil for none.
    var mode: String? {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    func set(_ bindings: [String: String], modes: [String: [String: String]] = [:]) {
        problems = []
        let keys = parse(bindings, prefix: "")
        var byMode: [String: [UInt16: [(KeySpec, [Command])]]] = [:]
        for (name, keys) in modes { byMode[name] = parse(keys, prefix: "modes.\(name).") }
        lock.withLock {
            byKey = keys
            modeKeys = byMode
            if let m = _mode, byMode[m] == nil { _mode = nil }
        }
    }

    private func parse(_ bindings: [String: String], prefix: String) -> [UInt16: [(KeySpec, [Command])]] {
        var out: [UInt16: [(KeySpec, [Command])]] = [:]
        for (key, text) in bindings {
            guard let spec = KeySpec.parse(key) else { problems.append("\(prefix)“\(key)” is not a key"); continue }
            do {
                let cmds = try Command.parseAll(text)
                out[spec.keyCode, default: []].append((spec, cmds))
            } catch {
                problems.append("\(prefix)\(key): \(error)")
            }
        }
        // Bindings needing a specific side first, so "ralt+1" wins over "alt+1".
        for k in out.keys { out[k]!.sort { $0.0.sides.nonzeroBitCount > $1.0.sides.nonzeroBitCount } }
        return out
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<Hotkeys>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.handle(event) ? nil : Unmanaged.passUnretained(event)
        }
        // Last in the chain, after key remappers such as a Caps Lock → hyper key app, which add
        // the modifier flags in their own tap.
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        guard let src = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        source = src
        EventTapThread.shared.add(src)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    enum Outcome: Equatable {
        /// Not a binding: the key goes on to its app.
        case pass
        /// A binding's repeat while the last one hasn't run yet: swallowed, nothing runs.
        case swallow
        case run([Command])
    }

    /// What a key press does (any thread).
    func match(code: UInt16, flags: UInt64, isRepeat: Bool) -> Outcome {
        lock.withLock {
            let modeList = _mode.flatMap { modeKeys[$0]?[code] } ?? []
            for (spec, cmds) in modeList + (byKey[code] ?? []) where spec.matches(keyCode: code, flags: flags) {
                // Key repeat of a binding (holding the key) runs it again, like skhd, but never
                // more often than the main thread gets through them.
                if isRepeat {
                    if repeatPending { return .swallow }
                    repeatPending = true
                }
                return .run(cmds)
            }
            return .pass
        }
    }

    /// The main thread ran a repeat: the next one may go.
    func repeatRan() { lock.withLock { repeatPending = false } }

    private func handle(_ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        switch match(code: code, flags: event.flags.rawValue, isRepeat: isRepeat) {
        case .pass: return false
        case .swallow: return true
        case .run(let cmds):
            DispatchQueue.main.async { [weak self] in
                if isRepeat { self?.repeatRan() }
                self?.run?(cmds)
            }
            return true
        }
    }
}
