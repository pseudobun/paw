import AppKit
import PawCore
import Testing
@preconcurrency @testable import paw

/// Event taps off the main thread, seam panels reused across switches, bounded caches.
@MainActor
struct EventAndRedrawTests {
    // MARK: Key bindings

    private func hotkeys(_ bindings: [String: String], modes: [String: [String: String]] = [:]) -> Hotkeys {
        let h = Hotkeys()
        h.set(bindings, modes: modes)
        return h
    }

    private func key(_ spec: String) -> (UInt16, UInt64) {
        let k = KeySpec.parse(spec)!
        // The flags a press of exactly this combination carries.
        var flags: UInt64 = 0
        if k.mods.contains(.alt) { flags |= CGEventFlags.maskAlternate.rawValue }
        if k.mods.contains(.cmd) { flags |= CGEventFlags.maskCommand.rawValue }
        if k.mods.contains(.ctrl) { flags |= CGEventFlags.maskControl.rawValue }
        if k.mods.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
        return (k.keyCode, flags)
    }

    @Test func aBindingRunsItsCommandsAndOtherKeysPass() throws {
        let h = hotkeys(["alt+h": "focus west"])
        let (code, flags) = key("alt+h")
        #expect(h.match(code: code, flags: flags, isRepeat: false) == .run(try Command.parseAll("focus west")))
        let (other, _) = key("alt+j")
        #expect(h.match(code: other, flags: flags, isRepeat: false) == .pass)
        #expect(h.match(code: code, flags: 0, isRepeat: false) == .pass, "without its modifier")
    }

    @Test func heldKeyRepeatsNeverPileUp() {
        let h = hotkeys(["alt+l": "resize east 20"])
        let (code, flags) = key("alt+l")
        #expect(h.match(code: code, flags: flags, isRepeat: false) != .pass)
        // The first repeat goes; the rest are swallowed until the main thread has run it.
        #expect(h.match(code: code, flags: flags, isRepeat: true) != .swallow)
        for _ in 0..<20 { #expect(h.match(code: code, flags: flags, isRepeat: true) == .swallow) }
        h.repeatRan()
        #expect(h.match(code: code, flags: flags, isRepeat: true) != .swallow)
        // A fresh press always runs.
        #expect(h.match(code: code, flags: flags, isRepeat: false) != .swallow)
    }

    @Test func modeKeysComeFirst() throws {
        let h = hotkeys(["alt+r": "layout bsp"], modes: ["resize": ["alt+r": "layout stack"]])
        let (code, flags) = key("alt+r")
        #expect(h.match(code: code, flags: flags, isRepeat: false) == .run(try Command.parseAll("layout bsp")))
        h.mode = "resize"
        #expect(h.match(code: code, flags: flags, isRepeat: false) == .run(try Command.parseAll("layout stack")))
        h.set(["alt+r": "layout bsp"])
        #expect(h.mode == nil, "a mode the new config doesn't have is left")
    }

    @Test func matchingWhileTheConfigChangesIsSafe() {
        let h = hotkeys(["alt+h": "focus west"])
        let (code, flags) = key("alt+h")
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for _ in 0..<20_000 { _ = h.match(code: code, flags: flags, isRepeat: false) }
            done.signal()
        }
        for i in 0..<200 { h.set(i % 2 == 0 ? ["alt+h": "focus west"] : ["alt+j": "focus east"]) }
        done.wait()
    }

    // MARK: Mouse

    @Test func theMouseTapListensOnlyForWhatTheConfigUses() {
        let scroll = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let gesture = CGEventMask(1) << 29
        let button = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        #expect(MouseGestures.mask(zoom: false, buttons: false) == 0, "no tap at all")
        let zoomOnly = MouseGestures.mask(zoom: true, buttons: false)
        #expect(zoomOnly & scroll != 0 && zoomOnly & gesture != 0 && zoomOnly & button == 0)
        let buttonsOnly = MouseGestures.mask(zoom: false, buttons: true)
        #expect(buttonsOnly & button != 0 && buttonsOnly & scroll == 0 && buttonsOnly & gesture == 0)
    }

    @Test func theTapThreadRunsSourcesOffTheMainThread() async {
        let ran = await Self.runOnTapThread()
        #expect(ran.onMain == false)
        #expect(ran.onTapThread == true)
    }

    /// A one-shot timer on the tap thread's run loop: where did it fire?
    nonisolated static func runOnTapThread() async -> (onMain: Bool, onTapThread: Bool) {
        await withCheckedContinuation { (c: CheckedContinuation<(onMain: Bool, onTapThread: Bool), Never>) in
            let fire: @Sendable (CFRunLoopTimer?) -> Void = { _ in
                c.resume(returning: (Thread.isMainThread, EventTapThread.isCurrent))
            }
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.01, 0, 0, 0, fire)
            let loop = EventTapThread.shared.runLoop
            CFRunLoopAddTimer(loop, timer, .commonModes)
            CFRunLoopWakeUp(loop)
        }
    }

    // MARK: Seams

    private func seams(_ ws: String, _ n: Int) -> [WindowManager.SeamInfo] {
        let split = ObjectIdentifier(NSObject())
        return (0..<n).map { i in
            .init(key: "\(ws)-\(i)", workspace: ws, split: split, index: i, axis: .horizontal,
                  frame: CGRect(x: 100 * Double(i + 1), y: 0, width: 8, height: 400), splitFrame: CGRect(x: 0, y: 0, width: 800, height: 400))
        }
    }

    @Test func switchingWorkspacesReusesSeamPanels() {
        let handles = SeamHandles(wm: nil)
        handles.apply(seams("1", 3), accent: ARGB(0xffff_ffff))
        #expect(handles.created == 3)
        // Every seam of the next workspace is new: the same panels show them.
        for i in 0..<50 { handles.apply(seams(i % 2 == 0 ? "2" : "1", 3), accent: ARGB(0xffff_ffff)) }
        #expect(handles.created == 3)
        #expect(handles.shownCount == 3)
        handles.apply(seams("3", 5), accent: ARGB(0xffff_ffff))
        #expect(handles.created == 5)
        handles.hideAll()
        #expect(handles.shownCount == 0)
        handles.apply(seams("4", 4), accent: ARGB(0xffff_ffff))
        #expect(handles.created == 5, "hidden panels come back")
        handles.hideAll()
    }

    // MARK: Caches

    @Test func iconImagesComeInAFewSizes() {
        #expect(AppColors.bucket(1) == 16)
        #expect(AppColors.bucket(16) == 16)
        #expect(AppColors.bucket(17) == 32)
        #expect(AppColors.bucket(100) == 128)
        #expect(AppColors.bucket(5000) == 1024)
        // Every size from 1 to 1024 px: seven images, not a thousand.
        #expect(Set((1...1024).map(AppColors.bucket)).count == 7)
    }

    @Test func liveWindowsAsksAboutPawsWindowsOnly() {
        #expect(WindowManager.liveWindows([]).isEmpty)
        #expect(WindowManager.liveWindows([4_000_000_001, 4_000_000_002]).isEmpty, "windows that don't exist")
    }

    @Test func queryIsEncodedOffTheMainThread() {
        let json = IPC.prettyJSON([["id": "1", "windows": [["id": 3, "app": "TextEdit"]]]])
        #expect(json.contains("\"app\" : \"TextEdit\""))
        #expect(IPC.prettyJSON(["bad": Double.nan]) == "", "not JSON: empty, not a crash")
    }
}
