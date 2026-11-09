import AppKit
import PawCore

/// Global key bindings through a session event tap (needs Accessibility, like the rest of paw).
/// Unlike Carbon hotkeys it tells left from right modifiers, so "ralt+1" works.
final class Hotkeys {
    private var byKey: [UInt16: [(KeySpec, [Command])]] = [:]
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var run: (([Command]) -> Void)?
    private(set) var problems: [String] = []

    func set(_ bindings: [String: String]) {
        byKey = [:]
        problems = []
        for (key, text) in bindings {
            guard let spec = KeySpec.parse(key) else { problems.append("“\(key)” is not a key"); continue }
            do {
                let cmds = try Command.parseAll(text)
                byKey[spec.keyCode, default: []].append((spec, cmds))
            } catch {
                problems.append("\(key): \(error)")
            }
        }
        // Bindings needing a specific side first, so "ralt+1" wins over "alt+1".
        for k in byKey.keys { byKey[k]!.sort { $0.0.sides.nonzeroBitCount > $1.0.sides.nonzeroBitCount } }
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
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(_ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let list = byKey[code] else { return false }
        let flags = event.flags.rawValue
        for (spec, cmds) in list where spec.matches(keyCode: code, flags: flags) {
            // Key repeat of a binding (holding the key) runs it again, like skhd.
            DispatchQueue.main.async { [weak self] in self?.run?(cmds) }
            return true
        }
        return false
    }
}
