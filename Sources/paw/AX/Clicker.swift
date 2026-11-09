import AppKit
import ApplicationServices
import PawCore

/// Clicks an element: AXPress when the element supports it (no pointer movement), otherwise a
/// synthesized mouse click at the centre of its visible part, with the pointer put back after.
enum Clicker {
    enum Kind: Equatable {
        case primary
        /// Shift on the last key.
        case right
        /// Cmd on the last key (open in new tab…).
        case command
        /// The last key typed twice.
        case double
        /// Option on the last key: move the pointer there without clicking.
        case hover
    }

    static func kind(for flags: CGEventFlags) -> Kind {
        if flags.contains(.maskCommand) { return .command }
        if flags.contains(.maskShift) { return .right }
        if flags.contains(.maskAlternate) { return .hover }
        return .primary
    }

    static func perform(_ kind: Kind, on e: Element, restoreCursor: Bool) {
        let point = ScreenGeometry.clickPoint(e.frame, clip: e.clip)
        switch kind {
        case .hover:
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(1)
            postMove(to: point)
        case .double:
            mouse(at: point, button: .left, count: 2, flags: [], restore: restoreCursor)
        case .command:
            mouse(at: point, button: .left, count: 1, flags: .maskCommand, restore: restoreCursor)
        case .right:
            Collector.queue.async {
                if e.ref.actions.contains("AXShowMenu"), e.ref.perform("AXShowMenu") { return }
                DispatchQueue.main.async { mouse(at: point, button: .right, count: 1, flags: [], restore: restoreCursor) }
            }
        case .primary:
            if ElementRules.prefersMouse(role: e.role) {
                mouse(at: point, button: .left, count: 1, flags: [], restore: restoreCursor)
                return
            }
            Collector.queue.async {
                let canPress = e.canPress ?? e.ref.actions.contains("AXPress")
                if canPress, e.ref.perform(kAXPressAction) { return }
                if e.role == "AXMenuBarItem" || e.role == "AXMenuItem", e.ref.perform(kAXPickAction) { return }
                DispatchQueue.main.async { mouse(at: point, button: .left, count: 1, flags: [], restore: restoreCursor) }
            }
        }
    }

    /// Clicks with real mouse events. `count` 2 sends a full double click (click states 1 and 2).
    static func mouse(at point: CGPoint, button: CGMouseButton, count: Int, flags: CGEventFlags, restore: Bool) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        let (downType, upType): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        postMove(to: point)
        for i in 1...max(1, count) {
            for type in [downType, upType] {
                guard let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { continue }
                ev.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                ev.flags = flags
                ev.post(tap: .cghidEventTap)
            }
        }
        guard restore, let original else { return }
        // Give the target a moment to read the click's location before the pointer moves back.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) {
            CGWarpMouseCursorPosition(original)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    static func postMove(to point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
