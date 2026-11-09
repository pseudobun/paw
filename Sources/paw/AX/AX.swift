import AppKit
import ApplicationServices

/// Thin helpers over the AXUIElement C API. Every call can block for up to the messaging
/// timeout, so they run on the collector's queue, never on the main thread.
extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()

    static func app(_ pid: pid_t, timeout: Float) -> AXUIElement {
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, timeout)
        return e
    }

    func value(_ attr: String) -> AnyObject? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success else { return nil }
        return v
    }

    func string(_ attr: String) -> String? { value(attr) as? String }

    func bool(_ attr: String) -> Bool? { (value(attr) as? NSNumber)?.boolValue }

    func element(_ attr: String) -> AXUIElement? { AX.element(value(attr)) }

    func elements(_ attr: String) -> [AXUIElement] {
        guard let arr = value(attr) as? [AnyObject] else { return [] }
        return arr.compactMap(AX.element)
    }

    /// One round trip for several attributes; a missing one comes back as nil.
    func values(_ attrs: [String]) -> [AnyObject?] {
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(self, attrs as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out)
        guard err == .success, let arr = out as? [AnyObject], arr.count == attrs.count else {
            return Array(repeating: nil, count: attrs.count)
        }
        return arr.map { AX.isError($0) ? nil : $0 }
    }

    var actions: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(self, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    @discardableResult
    func set(_ attr: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attr as CFString, value) == .success
    }

    var frame: CGRect? {
        let v = values([kAXPositionAttribute, kAXSizeAttribute])
        return AX.frame(position: v[0], size: v[1])
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    /// `AXUIElementsForSearchPredicate`: WebKit and Chromium answer it for a whole web area
    /// in one call, which is far faster than walking the DOM tree.
    func search(keys: [String], limit: Int) -> [AXUIElement]? {
        let predicate: [String: Any] = [
            "AXSearchKey": keys,
            "AXResultsLimit": limit,
            "AXDirection": "AXDirectionNext",
            "AXVisibleOnly": true,
            "AXImmediateDescendantsOnly": false,
        ]
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(self, "AXUIElementsForSearchPredicate" as CFString,
                                                             predicate as CFDictionary, &out)
        guard err == .success, let arr = out as? [AnyObject] else { return nil }
        return arr.compactMap(AX.element)
    }
}

enum AX {
    static func element(_ v: AnyObject?) -> AXUIElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func isError(_ v: AnyObject) -> Bool {
        CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError
    }

    static func frame(position: AnyObject?, size: AnyObject?) -> CGRect? {
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func text(_ v: AnyObject?, limit: Int = 160) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.count > limit ? String(t.prefix(limit)) : t
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (once per launch) when paw is not trusted yet.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
