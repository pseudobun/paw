import AppKit

/// Focusing one window of an app the way yabai does without its scripting addition: SkyLight's
/// front-process call with the window id, two synthetic "make key window" event records, then
/// AXRaise. NSRunningApplication.activate alone brings every window of the app forward and is
/// refused for background apps since macOS 14.
enum SkyLight {
    private typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let setFront: SetFront? = sym("_SLPSSetFrontProcessWithOptions", in: handle)
    private static let post: PostEvent? = sym("SLPSPostEventRecordTo", in: handle)
    private static let getPSN: GetPSN? = sym("GetProcessForPID", in: UnsafeMutableRawPointer(bitPattern: -2)) // RTLD_DEFAULT

    private static func sym<T>(_ name: String, in h: UnsafeMutableRawPointer?) -> T? {
        guard let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let mainConnection: MainConnection? = sym("SLSMainConnectionID", in: handle)
    private static let copyManagedDisplays: CopyManagedDisplays? = sym("SLSCopyManagedDisplays", in: handle)
    private static let copyManagedSpaces: CopyManagedSpaces? = sym("SLSCopyManagedDisplaySpaces", in: handle)

    private typealias QueryWindows = @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias CopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias AdvanceWindow = @convention(c) (CFTypeRef) -> Bool
    private typealias CornerRadii = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias WindowBounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> CGError
    private static let queryWindows: QueryWindows? = sym("SLSWindowQueryWindows", in: handle)
    private static let copyWindows: CopyWindows? = sym("SLSWindowQueryResultCopyWindows", in: handle)
    private static let advanceWindow: AdvanceWindow? = sym("SLSWindowIteratorAdvance", in: handle)
    private static let cornerRadii: CornerRadii? = sym("SLSWindowIteratorGetCornerRadii", in: handle)
    private static let windowBounds: WindowBounds? = sym("SLSGetWindowBounds", in: handle)

    /// macOS 26+: missing symbols or invalid results leave the configured radius in use.
    static func cornerRadius(_ id: UInt32) -> CGFloat? {
        guard let mainConnection, let queryWindows, let copyWindows, let advanceWindow, let cornerRadii,
              let query = queryWindows(mainConnection(), [id] as CFArray, 0)?.takeRetainedValue(),
              let iterator = copyWindows(query)?.takeRetainedValue(), advanceWindow(iterator),
              let radii = cornerRadii(iterator)?.takeRetainedValue() as? [NSNumber],
              let radius = radii.first?.doubleValue, radius.isFinite, radius >= 0 else { return nil }
        // shortcut: one radius for all corners, use a per-corner path if asymmetric windows need it.
        return CGFloat(radius)
    }

    /// WindowServer bounds are in points and don't wait for the app to answer AX.
    static func frame(_ id: UInt32) -> CGRect? {
        guard let mainConnection, let windowBounds else { return nil }
        var frame = CGRect.zero
        guard windowBounds(mainConnection(), id, &frame) == .success,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    /// Display UUIDs in the window server's order, the order sketchybar numbers displays in
    /// (its arrangement-id is the 1-based position here).
    static func managedDisplayUUIDs() -> [String] {
        guard let mainConnection, let copyManagedDisplays, let list = copyManagedDisplays(mainConnection())?.takeRetainedValue() else { return [] }
        return (list as? [String]) ?? []
    }

    /// Live topology: com.apple.spaces preferences can retain a disconnected display's old layout.
    static func nativeDesktopCounts() -> [Int]? {
        guard let mainConnection, let copyManagedSpaces,
              let list = copyManagedSpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return nativeDesktopCounts(in: list)
    }

    static func nativeDesktopCounts(in displays: [[String: Any]]) -> [Int]? {
        guard !displays.isEmpty else { return nil }
        var counts: [Int] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]], !spaces.isEmpty else { return nil }
            let types = spaces.compactMap { $0["type"] as? Int }
            guard types.count == spaces.count else { return nil }
            // Full-screen apps have their own Spaces; count only normal desktops.
            let desktops = types.filter { $0 == 0 }.count
            guard desktops > 0 else { return nil }
            counts.append(desktops)
        }
        return counts
    }

    static func nativeSpacesStatus(counts: [Int]?) -> String {
        guard let counts, !counts.isEmpty else { return "unavailable: check Mission Control; keep one desktop per display" }
        guard counts.contains(where: { $0 > 1 }) else { return "ok: one macOS desktop per display" }
        let totals = counts.map(String.init).joined(separator: ", ")
        return "warning: macOS desktops per display: \(totals). Keep one per display in Mission Control; extra desktops can hide windows and switch focus."
    }

    static var nativeSpacesStatus: String { nativeSpacesStatus(counts: nativeDesktopCounts()) }

    static var available: Bool { setFront != nil && post != nil && getPSN != nil }

    /// Focuses one window, raising it unless `raise` is false (focus follows mouse; yabai's
    /// autofocus). Falls back to activating the app.
    static func focus(pid: pid_t, windowID: UInt32, element: AXUIElement, raise: Bool = true) {
        guard let setFront, let post, let getPSN else {
            NSRunningApplication(processIdentifier: pid)?.activate()
            element.perform(kAXRaiseAction)
            return
        }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return }
        // Another window of the app in front: it loses key first. Read here, when the request
        // runs, so it is the window that has focus now. Some apps get confused when both
        // records arrive at once (yabai waits 40 ms).
        if !raise, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let current = AXUIElementCreateApplication(pid).element(kAXFocusedWindowAttribute)?.windowID, current != windowID {
            var lose = keyRecord(current, kind: 0x0d, state: 0x02), gain = keyRecord(windowID, kind: 0x0d, state: 0x01)
            _ = post(&psn, &lose)
            usleep(40000)
            _ = post(&psn, &gain)
        }
        _ = setFront(&psn, windowID, 0x200) // kCPSUserGenerated
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = keyRecord(windowID, kind: kind)
            _ = post(&psn, &bytes)
        }
        if raise { element.perform(kAXRaiseAction) }
    }

    /// One SkyLight event record for `windowID`: kind 0x01/0x02 make it key (with the 0xff
    /// block), 0x0d with `state` 0x02/0x01 has it lose or gain key.
    static func keyRecord(_ windowID: UInt32, kind: UInt8, state: UInt8? = nil) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x08] = kind
        if let state {
            bytes[0x8a] = state
        } else {
            bytes[0x3a] = 0x10
            for i in 0x20..<0x30 { bytes[i] = 0xff }
        }
        withUnsafeBytes(of: windowID.littleEndian) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        return bytes
    }
}
