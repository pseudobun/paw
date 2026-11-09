import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()

    func value(_ attr: String) -> AnyObject? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success else { return nil }
        return v
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
        AXUIElementSetAttributeValue(self, attr as CFString, value) == .success
    }

    func isSettable(_ attr: String) -> Bool {
        var b: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attr as CFString, &b) == .success && b.boolValue
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
        AXUIElementPerformAction(self, action as CFString) == .success
    }
}

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
