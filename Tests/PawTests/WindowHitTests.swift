import AppKit
import PawCore
import Testing
@testable import paw

struct WindowHitTests {
    @Test func popUpMenusAreNotManaged() {
        #expect(WindowManager.isMenuLayer(Int(CGWindowLevelForKey(.popUpMenuWindow))))
        #expect(WindowManager.isMenuLayer(Int(CGWindowLevelForKey(.assistiveTechHighWindow))))
        #expect(!WindowManager.isMenuLayer(Int(CGWindowLevelForKey(.normalWindow))))
        #expect(!WindowManager.isMenuLayer(Int(CGWindowLevelForKey(.floatingWindow))))
        #expect(!WindowManager.isMenuLayer(Int(CGWindowLevelForKey(.modalPanelWindow))))
    }

    @Test func placeholderStandsInForItsParkedWindow() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let placeholder = info(100, frame: frame, layer: -1)
        let point = CGPoint(x: 400, y: 300)
        #expect(WindowManager.topWindow(at: point, in: [placeholder], standIns: [100: 1], isManaged: { _ in false }) == 1)
        #expect(WindowManager.topWindow(at: point, in: [info(2, frame: frame), placeholder],
                                        standIns: [100: 1], isManaged: { $0 == 2 }) == 2)
        #expect(WindowManager.topWindow(at: point, in: [info(2, frame: frame), placeholder],
                                        standIns: [100: 1], isManaged: { _ in false }) == nil)
        #expect(WindowManager.topWindow(at: point, in: [placeholder], ignoring: [1],
                                        standIns: [100: 1], isManaged: { _ in false }) == nil)
    }

    @Test func closingWindowDoesNotOccludeHoveredSurvivor() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let list = [info(1, frame: frame), info(2, frame: frame)]
        let hovered = WindowManager.topWindow(at: CGPoint(x: 400, y: 300), in: list,
                                              ignoring: [1], isManaged: { $0 == 2 })
        #expect(hovered == 2)
    }

    @Test func closeFocusPrefersHoverThenExistingFallbacks() {
        let ws = Workspace(name: "1")
        let area = CGRect(x: 0, y: 0, width: 800, height: 600)
        for id: WindowID in [1, 2, 3, 4] { ws.insert(id, area: area) }
        ws.focused = 1
        ws.remove(1)

        // Hover can belong to another visible workspace, even when this one becomes empty.
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: 9, appFocused: 4, sameApp: { $0 == 3 }) == 9)
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: nil, appFocused: 4, sameApp: { $0 == 3 }) == 4)
        // The app's focused window on a hidden workspace must not pull focus there.
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: nil, appFocused: 9, sameApp: { $0 == 3 }) == 3)
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: nil, appFocused: nil, sameApp: { _ in false }) == 2)

        for id in ws.allWindows { ws.remove(id) }
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: 9, appFocused: nil, sameApp: { _ in false }) == 9)
        #expect(WindowManager.focusAfterRemoval(in: ws, hovered: nil, appFocused: nil, sameApp: { _ in false }) == nil)
    }

    /// Focus follows mouse leaves the pointer inside the window being closed: nothing is under
    /// it until the neighbours retile, so the hover must come from the layout to come.
    @Test func closeFocusPicksTheTileThatRetilesUnderThePointer() throws {
        let ws = Workspace(name: "1")
        let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for id: WindowID in [1, 2, 3] { ws.insert(id, area: area) }
        let closing = try #require(TreeLayout.windowFrames(ws, in: area, gap: 8)[3])
        let p = CGPoint(x: closing.midX, y: closing.midY)
        ws.focused = 3
        ws.remove(3)
        let frames = TreeLayout.windowFrames(ws, in: area, gap: 8)
        let retiled = try #require([WindowID(1), 2].first { frames[$0]?.contains(p) == true })
        #expect(retiled != ws.focused, "The fallback alone must not already pass")

        let underneath = WindowManager.windowUnder(p, after: ws, frames: frames, gap: 8)
        #expect(underneath == retiled)
        #expect(WindowManager.topWindow(at: p, in: [], fallback: underneath, isManaged: { _ in false }) == retiled)
        // The pointer on the seam between two retiled tiles still picks one of them.
        let seam = CGPoint(x: frames[1]!.maxX + 4, y: p.y)
        #expect([1, 2].contains(WindowManager.windowUnder(seam, after: ws, frames: frames, gap: 8)))
        // Actual hovered tiles, floating windows and other displays all beat future geometry.
        for id: WindowID in [1, 4, 9] {
            #expect(WindowManager.topWindow(at: p, in: [info(id, frame: area)], fallback: underneath,
                                            isManaged: { $0 == id }) == id)
        }
        // A real overlay must block the future tile just as it blocks an existing one.
        #expect(WindowManager.topWindow(at: p, in: [info(99, frame: area, layer: 25)], fallback: underneath,
                                        isManaged: { _ in false }) == nil)
        #expect(WindowManager.windowUnder(CGPoint(x: -100, y: -100), after: ws, frames: frames, gap: 8) == nil)
    }

    @Test func screenshotOverlayBlocksFocusUntilCaptureCloses() {
        let left = info(1, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900))
        let right = info(2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let capture = info(3, frame: CGRect(x: -1440, y: 0, width: 3360, height: 1080), layer: 25)
        for (point, id) in [(CGPoint(x: -500, y: 300), WindowID(1)), (CGPoint(x: 500, y: 300), WindowID(2))] {
            #expect(WindowManager.topWindow(at: point, in: [capture, left, right],
                                            isManaged: { $0 == 1 || $0 == 2 }) == nil)
            #expect(WindowManager.topWindow(at: point, in: [left, right],
                                            isManaged: { $0 == 1 || $0 == 2 }) == id)
        }
    }

    @Test func filePickerBlocksHoverFocusThroughItsOverlap() {
        let background = CGRect(x: 0, y: 0, width: 800, height: 600)
        let picker = CGRect(x: 400, y: 200, width: 600, height: 300)
        let list = [info(2, frame: picker), info(1, frame: background)]
        #expect(WindowManager.topWindow(at: CGPoint(x: 500, y: 300), in: list, isManaged: { $0 == 1 }) == nil)
        #expect(WindowManager.topWindow(at: CGPoint(x: 100, y: 300), in: list, isManaged: { $0 == 1 }) == 1)
    }

    @Test(arguments: [0, 3, 8]) func dialogsAtNormalAndElevatedLevelsBlockFocus(layer: Int) {
        let frame = CGRect(x: -600, y: 100, width: 600, height: 400)
        let list = [info(2, frame: frame, layer: layer), info(1, frame: frame)]
        let point = CGPoint(x: -300, y: 200)

        #expect(WindowManager.topWindow(at: point, in: list, isManaged: { $0 == 1 }) == nil)
        #expect(WindowManager.topWindow(at: point, in: list, isManaged: { _ in true }) == 2)
    }

    /// The window server sometimes lists the pointer itself as a small window at cursor level;
    /// it sits under every pointer position and must not count as a dialog.
    @Test func cursorWindowDoesNotBlockFocus() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let point = CGPoint(x: 400, y: 300)
        let cursor = info(3, frame: CGRect(x: 395, y: 295, width: 28, height: 40),
                          layer: Int(CGWindowLevelForKey(.cursorWindow)))
        #expect(WindowManager.topWindow(at: point, in: [cursor, info(1, frame: frame)], isManaged: { $0 == 1 }) == 1)
        #expect(WindowManager.topWindow(at: point, in: [cursor], fallback: 2, isManaged: { _ in false }) == 2)
    }

    @Test func clickThroughPawOverlaysDoNotBlockFocus() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let list = [info(3, frame: frame, layer: 3), info(2, frame: frame), info(1, frame: frame)]
        let point = CGPoint(x: 400, y: 300)

        #expect(WindowManager.topWindow(at: point, in: list, ignoring: [2, 3], isManaged: { $0 == 1 }) == 1)
    }

    @Test func hiddenAndMissingWindowsAreNotFocusTargets() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let list = [info(1, frame: frame)]

        #expect(WindowManager.topWindow(at: CGPoint(x: 400, y: 300), in: list, isManaged: { _ in false }) == nil)
        #expect(WindowManager.topWindow(at: CGPoint(x: 900, y: 300), in: list, isManaged: { _ in true }) == nil)
        #expect(WindowManager.topWindow(at: .zero, in: [], isManaged: { _ in true }) == nil)
    }

    private func info(_ id: WindowID, frame: CGRect, layer: Int = 0) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
}

struct FloatPlacementTests {
    @Test func newFloatsCentreInTheirArea() {
        let area = CGRect(x: 0, y: 25, width: 1000, height: 800)
        #expect(WindowManager.centered(CGSize(width: 400, height: 200), in: area) == CGRect(x: 300, y: 325, width: 400, height: 200))
        // Larger than the area: top-left stays inside it.
        #expect(WindowManager.centered(CGSize(width: 1200, height: 900), in: area).origin == CGPoint(x: 0, y: 25))
    }

    @Test func keyRecordsCarryWindowAndState() {
        let gain = SkyLight.keyRecord(0x01020304, kind: 0x0d, state: 0x01)
        #expect(gain.count == 0xf8 && gain[0x08] == 0x0d && gain[0x8a] == 0x01 && gain[0x3a] == 0)
        #expect(Array(gain[0x3c..<0x40]) == [0x04, 0x03, 0x02, 0x01])
        let key = SkyLight.keyRecord(7, kind: 0x01)
        #expect(key[0x3a] == 0x10 && key[0x20] == 0xff && key[0x2f] == 0xff && key[0x8a] == 0)
    }

    @Test func floatsRaiseBackToFrontKeepingTheirOrder() {
        // 3 is in front of 1; 2 isn't on screen.
        #expect(WindowManager.backToFront([1, 2, 3], stacking: [9, 3, 1]) == [2, 1, 3])
    }
}
