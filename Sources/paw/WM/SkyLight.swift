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
    private static let mainConnection: MainConnection? = sym("SLSMainConnectionID", in: handle)
    private static let copyManagedDisplays: CopyManagedDisplays? = sym("SLSCopyManagedDisplays", in: handle)

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

    static var available: Bool { setFront != nil && post != nil && getPSN != nil }

    /// Focuses and raises one window. Falls back to activating the app.
    static func focus(pid: pid_t, windowID: UInt32, element: AXUIElement) {
        guard let setFront, let post, let getPSN else {
            NSRunningApplication(processIdentifier: pid)?.activate()
            element.perform(kAXRaiseAction)
            return
        }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return }
        _ = setFront(&psn, windowID, 0x200) // kCPSUserGenerated
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = kind
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: windowID.littleEndian) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            _ = post(&psn, &bytes)
        }
        element.perform(kAXRaiseAction)
    }
}
