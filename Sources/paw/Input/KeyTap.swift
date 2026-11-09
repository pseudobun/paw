import AppKit
import Carbon.HIToolbox

/// While a mode is open, a session event tap takes every key before the frontmost app sees it,
/// so paw can read keys without becoming the active app. Mouse clicks pass through and close
/// the mode.
final class KeyTap {
    struct Key {
        let code: UInt16
        /// The key's character on the ASCII-capable layout, without modifiers ("a", ";").
        let char: Character?
        /// What the key types with its modifiers on the current input source (search queries).
        let text: String
        let flags: CGEventFlags
        let down: Bool
        let isRepeat: Bool

        var shift: Bool { flags.contains(.maskShift) }
        var command: Bool { flags.contains(.maskCommand) }
        var option: Bool { flags.contains(.maskAlternate) }
        var control: Bool { flags.contains(.maskControl) }
    }

    /// Return true to swallow the key.
    var onKey: ((Key) -> Bool)?
    var onFlags: ((CGEventFlags) -> Void)?
    var onMouseDown: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isEnabled = false

    /// Creates the tap the first time (needs Accessibility) and turns it on.
    @discardableResult
    func enable() -> Bool {
        if tap == nil { create() }
        guard let tap else { return false }
        KeyboardLayout.refresh()
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
        return true
    }

    func disable() {
        isEnabled = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func create() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.input.error("event tap: not allowed (Accessibility)")
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: false)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isEnabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if isEnabled { onMouseDown?() }
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            if isEnabled { onFlags?(event.flags) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            guard isEnabled, let onKey else { return Unmanaged.passUnretained(event) }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
            let text = String(utf16CodeUnits: buffer, count: length)
            let key = Key(code: code, char: KeyboardLayout.character(code), text: text, flags: event.flags, down: type == .keyDown,
                          isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            return onKey(key) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

/// Key code → character on the current ASCII-capable layout (so labels work the same with a
/// Slovenian or Cyrillic input source selected), cached per activation.
enum KeyboardLayout {
    private static var table: [UInt16: Character] = [:]

    static func character(_ code: UInt16) -> Character? {
        if table.isEmpty { refresh() }
        return table[code]
    }

    static func refresh() {
        var t: [UInt16: Character] = [:]
        if let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                    for code in UInt16(0)..<128 {
                        var dead: UInt32 = 0
                        var len = 0
                        var chars = [UniChar](repeating: 0, count: 4)
                        let err = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                                 OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
                        guard err == noErr, len == 1, let scalar = Unicode.Scalar(chars[0]) else { continue }
                        let c = Character(scalar)
                        if c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol { t[code] = Character(c.lowercased()) }
                    }
                }
            }
        }
        if t.isEmpty { t = fallback }
        table = t
    }

    /// US ANSI, for when the layout can't be read.
    private static let fallback: [UInt16: Character] = {
        var m: [UInt16: Character] = [:]
        for (name, code) in [("a", kVK_ANSI_A), ("s", kVK_ANSI_S), ("d", kVK_ANSI_D), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G),
                             ("h", kVK_ANSI_H), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), (";", kVK_ANSI_Semicolon),
                             ("q", kVK_ANSI_Q), ("w", kVK_ANSI_W), ("e", kVK_ANSI_E), ("r", kVK_ANSI_R), ("t", kVK_ANSI_T),
                             ("y", kVK_ANSI_Y), ("u", kVK_ANSI_U), ("i", kVK_ANSI_I), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
                             ("z", kVK_ANSI_Z), ("x", kVK_ANSI_X), ("c", kVK_ANSI_C), ("v", kVK_ANSI_V), ("b", kVK_ANSI_B),
                             ("n", kVK_ANSI_N), ("m", kVK_ANSI_M), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
                             ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
                             ("9", kVK_ANSI_9), ("0", kVK_ANSI_0), (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
                             ("/", kVK_ANSI_Slash), ("'", kVK_ANSI_Quote), ("[", kVK_ANSI_LeftBracket), ("]", kVK_ANSI_RightBracket),
                             ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal)] {
            m[UInt16(code)] = Character(name)
        }
        return m
    }()
}
