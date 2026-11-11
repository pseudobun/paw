import AppKit
import PawCore
import Testing
@testable import paw

struct WindowHitTests {
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
