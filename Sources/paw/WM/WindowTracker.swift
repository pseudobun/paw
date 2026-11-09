import AppKit
import ApplicationServices

/// Accessibility observers on every regular app: windows appearing, going away, moving,
/// minimising, and focus changes. Everything arrives on the main run loop.
final class WindowTracker {
    enum Event {
        case created(AXUIElement, pid_t)
        case destroyed(AXUIElement)
        case focused(pid_t)
        case moved(AXUIElement)
        case resized(AXUIElement)
        case minimized(AXUIElement)
        case deminimized(AXUIElement)
        case appHidden(pid_t)
        case appShown(pid_t)
        case titleChanged(AXUIElement)
    }

    var onEvent: ((Event) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]

    static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                   kAXApplicationHiddenNotification, kAXApplicationShownNotification]
    static let windowNotifications = [kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
                                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification]

    func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications { AXObserverAddNotification(observer, appElement, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    func watch(window: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications { AXObserverAddNotification(observer, window, n as CFString, refcon) }
    }

    func forget(_ pid: pid_t) {
        guard let o = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
    }

    func isObserving(_ pid: pid_t) -> Bool { observers[pid] != nil }

    private func handle(_ element: AXUIElement, _ n: String) {
        let e: Event
        switch n {
        case kAXWindowCreatedNotification: e = .created(element, element.pid)
        case kAXFocusedWindowChangedNotification: e = .focused(element.pid)
        case kAXUIElementDestroyedNotification: e = .destroyed(element)
        case kAXWindowMovedNotification: e = .moved(element)
        case kAXWindowResizedNotification: e = .resized(element)
        case kAXWindowMiniaturizedNotification: e = .minimized(element)
        case kAXWindowDeminiaturizedNotification: e = .deminimized(element)
        case kAXApplicationHiddenNotification: e = .appHidden(element.pid)
        case kAXApplicationShownNotification: e = .appShown(element.pid)
        case kAXTitleChangedNotification: e = .titleChanged(element)
        default: return
        }
        onEvent?(e)
    }
}
