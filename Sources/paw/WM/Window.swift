import AppKit
import PawCore

/// A window paw manages.
final class Window {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let app: String
    /// Last frame paw set or saw (AX, top-left origin).
    var frame: CGRect
    /// Where a floating window was before its workspace was hidden.
    var floatFrame: CGRect?
    var isHidden = false

    init(id: WindowID, element: AXUIElement, pid: pid_t, app: String, frame: CGRect) {
        self.id = id
        self.element = element
        self.pid = pid
        self.app = app
        self.frame = frame
        refreshTitle()
    }

    /// Kept up to date from title-changed notifications: reading it over AX each time (for every
    /// indicator, every focus change) is slow with busy apps.
    private(set) var title = ""

    @discardableResult
    func refreshTitle() -> Bool {
        let t = element.string(kAXTitleAttribute) ?? ""
        defer { title = t }
        return t != title
    }
    var isMinimized: Bool { element.bool(kAXMinimizedAttribute) ?? false }

    func readFrame() -> CGRect? {
        let f = element.frame
        if let f { frame = f }
        return f
    }

    /// Size, position, size: the second size fixes apps that clamp size to the old screen.
    func setFrame(_ r: CGRect) {
        element.setSize(r.size)
        element.setPosition(r.origin)
        element.setSize(r.size)
        frame = r
    }

    func setPosition(_ p: CGPoint) {
        element.setPosition(p)
        frame.origin = p
    }

    func focus() {
        SkyLight.focus(pid: pid, windowID: id, element: element)
    }
}
