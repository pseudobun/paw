import AppKit
import PawCore
import Testing
@testable import paw

@MainActor
@Suite(.serialized)
struct BorderTests {
    let screen = CGRect(x: 0, y: 0, width: 2000, height: 2000)
    let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

    func config() -> PawConfig.Border {
        var c = PawConfig.Border()
        c.enabled = true
        return c
    }

    @Test func unchangedAndTranslatedBordersReuseTheirPath() throws {
        let border = FocusBorder()
        defer { border.hide() }
        var c = config()
        border.show(frame, window: 42, above: false, screen: screen, config: c, radius: 26)
        let path = try #require(border.shape.path)
        #expect(border.panel.isVisible)

        border.show(frame, window: 42, above: false, screen: screen, config: c, radius: 26)
        #expect(border.shape.path === path)
        let panelFrame = border.panel.frame
        border.show(frame.offsetBy(dx: 50, dy: 20), window: 42, above: false, screen: screen, config: c, radius: 26)
        #expect(border.panel.frame != panelFrame)
        #expect(border.shape.path === path)

        c.color = ARGB(0xffff0000)
        border.show(frame.offsetBy(dx: 50, dy: 20), window: 42, above: false, screen: screen, config: c, radius: 26)
        #expect(border.shape.path === path)
        #expect(border.shape.strokeColor == c.color.cg)
    }

    @Test func zeroRadiusIsNotReplacedByFallbackAndChangesInvalidatePath() throws {
        let border = FocusBorder()
        defer { border.hide() }
        var c = config()
        border.show(frame, window: 42, above: false, screen: screen, config: c, radius: 0)
        let square = try #require(border.shape.path)
        let r = square.boundingBoxOfPath
        #expect(square == CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil))

        border.show(frame, window: 42, above: false, screen: screen, config: c)
        let fallback = try #require(border.shape.path)
        #expect(fallback == CGPath(roundedRect: r, cornerWidth: 15, cornerHeight: 15, transform: nil))
        #expect(fallback != square)

        c.width = 4
        border.show(frame, window: 42, above: false, screen: screen, config: c)
        #expect(border.shape.path != fallback)
        #expect(border.shape.lineWidth == 4)
        c.enabled = false
        border.show(frame, window: 42, above: false, screen: screen, config: c)
        #expect(!border.panel.isVisible)
        #expect(border.windowID == nil)
        c.enabled = true
        border.show(frame, window: 42, above: false, screen: screen, config: c)
        #expect(border.panel.isVisible)
        c.width = 0
        border.show(frame, window: 42, above: false, screen: screen, config: c)
        #expect(!border.panel.isVisible)
    }

    @Test func screenEdgesKeepTheFullStrokeVisibleWithTwoPointPadding() throws {
        let border = FocusBorder()
        defer { border.hide() }
        let edge = CGRect(x: 2, y: 1698, width: 400, height: 300)
        let c = config()
        func strokeBounds() throws -> CGRect {
            let path = try #require(border.shape.path)
            let cocoa = path.boundingBoxOfPath.offsetBy(dx: border.panel.frame.minX, dy: border.panel.frame.minY)
            return ScreenGeometry.axFrame(ofScreen: cocoa, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
                .insetBy(dx: -c.width / 2, dy: -c.width / 2)
        }
        border.show(edge, window: 42, above: false, screen: screen, config: c, radius: 26)
        let stroke = try strokeBounds()
        #expect(screen.insetBy(dx: -0.001, dy: -0.001).contains(stroke))
        #expect(abs(stroke.minX - screen.minX) < 0.001)
        #expect(abs(stroke.maxY - screen.maxY) < 0.001)
        #expect(abs(stroke.minY - (edge.minY - c.offset - c.width)) < 0.001)
        #expect(abs(stroke.maxX - (edge.maxX + c.offset + c.width)) < 0.001)

        let oldFrame = border.panel.frame
        let smaller = screen.insetBy(dx: 10, dy: 10)
        border.show(edge, window: 42, above: false, screen: smaller, config: c, radius: 26)
        #expect(border.panel.frame != oldFrame)
        #expect(try smaller.insetBy(dx: -0.001, dy: -0.001).contains(strokeBounds()))
    }

    @Test func changingFromPlaceholderToWindowRestoresNormalLevel() {
        let target = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        let border = FocusBorder()
        defer { border.hide(); target.close() }
        let id = UInt32(target.windowNumber)
        border.show(frame, window: id, above: false, screen: screen, config: config())
        #expect(border.panel.level.rawValue == NSWindow.Level.normal.rawValue - 1)
        border.show(frame, window: id, above: true, screen: screen, config: config())
        #expect(border.panel.level == .normal)
    }

    @Test func radiusQueriesAreCachedPerWindowIncludingUnavailableResults() {
        let element = AXUIElementCreateApplication(getpid())
        let a = Window(id: 1, element: element, pid: getpid(), app: "Test", frame: frame)
        let b = Window(id: 2, element: element, pid: getpid(), app: "Test", frame: frame)
        var calls = 0
        let query: (UInt32) -> CGFloat? = { id in calls += 1; return id == 1 ? 0 : nil }
        #expect(a.radiusForBorder(query: query) == 0)
        #expect(a.radiusForBorder(query: query) == 0)
        #expect(b.radiusForBorder(query: query) == nil)
        #expect(b.radiusForBorder(query: query) == nil)
        #expect(calls == 2)
        a.invalidateCornerRadius()
        #expect(a.radiusForBorder(query: { _ in calls += 1; return 26 }) == 26)
        #expect(calls == 3)
    }

    @Test func windowServerReadsPointBoundsAndRejectsMissingWindows() throws {
        _ = NSApplication.shared
        let target = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        defer { target.close() }
        target.orderBack(nil)
        target.display()
        // Commit AppKit's pending window transaction before asking WindowServer.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let id = UInt32(target.windowNumber)
        let actual = try #require(SkyLight.frame(id))
        let expected = ScreenGeometry.axFrame(ofScreen: target.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        #expect(actual == expected)
        if #available(macOS 26, *) {
            let radius = try #require(SkyLight.cornerRadius(id))
            #expect(radius.isFinite && radius >= 0)
        }
        #expect(SkyLight.frame(UInt32.max) == nil)
        #expect(SkyLight.cornerRadius(UInt32.max) == nil)
    }

    @Test func movingInvalidatesBoundsButOnlyResizingInvalidatesRadius() {
        let w = Window(id: 1, element: AXUIElementCreateApplication(getpid()), pid: getpid(), app: "Test", frame: frame)
        var calls = 0
        let query: (UInt32) -> CGFloat? = { _ in calls += 1; return 16 }
        #expect(w.radiusForBorder(query: query) == 16)
        w.borderFrame = frame
        w.borderNeedsRefresh = false
        w.setPosition(CGPoint(x: 200, y: 200))
        #expect(w.borderFrame == nil && w.borderNeedsRefresh)
        #expect(w.frame.origin == CGPoint(x: 200, y: 200))
        #expect(w.radiusForBorder(query: query) == 16 && calls == 1)
        w.setFrame(CGRect(x: 200, y: 200, width: 500, height: 400))
        #expect(w.radiusForBorder(query: query) == 16 && calls == 2)
    }

    @Test func tiledBordersUseDestinationDuringStartResizeAnimations() {
        let w = Window(id: 1, element: AXUIElementCreateApplication(getpid()), pid: getpid(), app: "Test", frame: frame)
        let target = CGRect(x: 600, y: 200, width: 500, height: 400)
        let animator = Animator()
        animator.settings = {
            var animation = PawConfig.Animation()
            animation.enabled = true
            animation.durationMs = 1000
            animation.resize = "start"
            return animation
        }
        defer { animator.stop() }
        animator.animate([(w, target)])
        #expect(animator.isRunning)
        #expect(w.borderFrame == nil)
        #expect(w.frame != target)
        #expect(w.frameForBorder(tile: target, placeholder: false) == target)

        let observed = CGRect(x: 600, y: 200, width: 504, height: 402)
        w.borderFrame = observed
        #expect(w.frameForBorder(tile: target, placeholder: false) == observed)
        #expect(w.frameForBorder(tile: target, placeholder: true) == target)
        #expect(w.frameForBorder(tile: nil, placeholder: true) == nil)
        #expect(w.frameForBorder(tile: nil, placeholder: false) == observed)
        w.borderFrame = nil
        #expect(w.frameForBorder(tile: nil, placeholder: false) == w.frame)
    }
}
