import Carbon.HIToolbox

/// A key binding like "ctrl+alt+left", "hyper+0x18", "ralt+shift+1" (skhd's names).
/// Left/right variants (lalt, ralt, lcmd, rcmd, lctrl, rctrl, lshift, rshift) need that side.
public struct KeySpec: Hashable, Sendable {
    public struct Mods: OptionSet, Hashable, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let cmd = Mods(rawValue: 1), ctrl = Mods(rawValue: 2), alt = Mods(rawValue: 4)
        public static let shift = Mods(rawValue: 8), fn = Mods(rawValue: 16)
        public static let hyper: Mods = [.cmd, .ctrl, .alt, .shift]
    }

    public let keyCode: UInt16
    public let mods: Mods
    /// Device-side bits that must be set (CGEventFlags low bits, e.g. 0x40 for right alt).
    public let sides: UInt64

    // CGEventFlags.
    static let shiftMask: UInt64 = 0x20000, ctrlMask: UInt64 = 0x40000, altMask: UInt64 = 0x80000
    static let cmdMask: UInt64 = 0x100000, fnMask: UInt64 = 0x800000
    static let lctrl: UInt64 = 0x1, lshift: UInt64 = 0x2, rshift: UInt64 = 0x4, lcmd: UInt64 = 0x8
    static let rcmd: UInt64 = 0x10, lalt: UInt64 = 0x20, ralt: UInt64 = 0x40, rctrl: UInt64 = 0x2000

    public init(keyCode: UInt16, mods: Mods, sides: UInt64 = 0) {
        self.keyCode = keyCode
        self.mods = mods
        self.sides = sides
    }

    public static func parse(_ text: String) -> KeySpec? {
        let parts = text.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init)
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        let code: UInt16
        if keyName.hasPrefix("0x"), let v = UInt16(keyName.dropFirst(2), radix: 16) { code = v }
        else if let v = keyCodes[keyName] { code = UInt16(v) }
        else { return nil }
        var mods: Mods = []
        var sides: UInt64 = 0
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "⌘": mods.insert(.cmd)
            case "lcmd": mods.insert(.cmd); sides |= lcmd
            case "rcmd": mods.insert(.cmd); sides |= rcmd
            case "ctrl", "control", "⌃": mods.insert(.ctrl)
            case "lctrl": mods.insert(.ctrl); sides |= lctrl
            case "rctrl": mods.insert(.ctrl); sides |= rctrl
            case "alt", "opt", "option", "⌥": mods.insert(.alt)
            case "lalt": mods.insert(.alt); sides |= lalt
            case "ralt": mods.insert(.alt); sides |= ralt
            case "shift", "⇧": mods.insert(.shift)
            case "lshift": mods.insert(.shift); sides |= lshift
            case "rshift": mods.insert(.shift); sides |= rshift
            case "fn": mods.insert(.fn)
            case "hyper": mods.formUnion(.hyper)
            case "meh": mods.formUnion([.ctrl, .alt, .shift])
            default: return nil
            }
        }
        return KeySpec(keyCode: code, mods: mods, sides: sides)
    }

    /// Whether a key-down with these CGEventFlags is this binding. Arrow and function keys carry
    /// the fn flag by themselves, so fn only counts when the binding asks for it.
    public func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        guard keyCode == self.keyCode else { return false }
        var have: Mods = []
        if flags & Self.cmdMask != 0 { have.insert(.cmd) }
        if flags & Self.ctrlMask != 0 { have.insert(.ctrl) }
        if flags & Self.altMask != 0 { have.insert(.alt) }
        if flags & Self.shiftMask != 0 { have.insert(.shift) }
        if mods.contains(.fn), flags & Self.fnMask != 0 { have.insert(.fn) }
        guard have == mods else { return false }
        return flags & sides == sides
    }

    public static let keyCodes: [String: Int] = {
        var m: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
            "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
            "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
        ]
        let f = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                 kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in f.enumerated() { m["f\(i + 1)"] = code }
        return m
    }()
}
