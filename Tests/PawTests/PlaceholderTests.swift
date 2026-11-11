import AppKit
import PawCore
import Testing
@testable import paw

@MainActor
struct PlaceholderTests {
    @Test func newPlaceholderStaysBelowInsetFocusBorder() throws {
        _ = NSApplication.shared
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = ScreenGeometry.axFrame(ofScreen: try #require(NSScreen.main).frame, primaryHeight: primaryHeight)
        let frame = CGRect(x: screen.minX + 100, y: screen.minY + 100, width: 200, height: 150)
        let target = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        let border = FocusBorder()
        let placeholders = Placeholders()
        let id = UInt32(target.windowNumber)
        var config = PawConfig.Border()
        config.enabled = true
        config.offset = -2
        let actions = Placeholders.Actions(focus: { _ in }, zoom: { _ in }, drag: { _, _ in }, drop: { _, _ in })
        defer {
            placeholders.apply([], style: Style(.init()), focusFollowsMouse: false, focusBorder: border, actions: actions)
            border.hide()
            target.close()
        }
        target.orderBack(nil)
        border.show(frame, window: id, above: true, screen: screen, config: config)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        target.orderOut(nil)
        border.show(frame, window: id, above: false, screen: screen, config: config)
        placeholders.apply([.init(id: id, app: "Test", title: "Test", frame: frame, focused: true)],
                           style: Style(.init()), focusFollowsMouse: false, focusBorder: border, actions: actions)
        let placeholder = try #require(NSApp.windows.first { ($0.contentView as? PlaceholderView)?.item?.id == id })
        // Commit AppKit ordering before inspecting the WindowServer's front-to-back list.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        // Only the onscreen query guarantees front-to-back ordering.
        let windows = try #require(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
        let ids = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
        let borderIndex = try #require(ids.firstIndex(of: border.panel.windowNumber))
        let placeholderIndex = try #require(ids.firstIndex(of: placeholder.windowNumber))
        #expect(borderIndex < placeholderIndex)
        #expect((placeholder.contentView as? PlaceholderView)?.focusBorderVisible == true)
        #expect(border.panel.parent === placeholder)

        let view = try #require(placeholder.contentView as? PlaceholderView)
        let item = Placeholders.Item(id: id, app: "Test", title: "Test", frame: frame, focused: true)
        let style = Style(PawConfig.Appearance())
        placeholders.apply([item], style: style, focusFollowsMouse: false, focusBorder: border, actions: actions)
        #expect(view.focusBorderVisible)
        border.hide()
        placeholders.apply([item], style: style, focusFollowsMouse: false, focusBorder: border, actions: actions)
        #expect(!view.focusBorderVisible, "restore the fallback when the external border hides")
        border.show(frame, window: id, above: false, screen: screen, config: config)
        placeholders.apply([item], style: style, focusFollowsMouse: false, focusBorder: border, actions: actions)
        #expect(view.focusBorderVisible, "remove the fallback when the external border returns")

        let moved = frame.offsetBy(dx: 40, dy: 20)
        border.show(moved, window: id, above: false, screen: screen, config: config)
        #expect(border.panel.parent == nil)
        let expected = border.panel.frame
        placeholders.apply([.init(id: id, app: "Test", title: "Test", frame: moved, focused: true)],
                           style: Style(.init()), focusFollowsMouse: false, focusBorder: border, actions: actions)
        #expect(border.panel.parent === placeholder)
        #expect(border.panel.frame == expected)
        border.hide()
        #expect(border.panel.parent == nil)

        border.show(moved, window: id, above: false, screen: screen, config: config)
        placeholders.apply([.init(id: id, app: "Test", title: "Test", frame: moved, focused: true)],
                           style: Style(.init()), focusFollowsMouse: false, focusBorder: border, actions: actions)
        #expect(border.panel.parent === placeholder)
        border.show(moved, window: id, above: true, screen: screen, config: config)
        #expect(border.panel.parent == nil)
        #expect(border.panel.level == .normal)
    }

    @Test func externalFocusBorderReplacesAccentWithFallbackWhenHidden() throws {
        let view = PlaceholderView(frame: CGRect(x: 0, y: 0, width: 160, height: 140))
        view.item = .init(id: 42, app: "Test", title: "Test", frame: view.bounds, focused: true)
        var appearance = PawConfig.Appearance()
        appearance.colors.accent = ARGB(0xffff0000)
        appearance.colors.island = ARGB(0xff000000)
        view.style = Style(appearance)

        func edgeIsAccent() throws -> Bool {
            let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 140,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: image))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            view.draw(view.bounds)
            let color = try #require(image.colorAt(x: 1, y: 70)?.usingColorSpace(.deviceRGB))
            return color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2
        }

        #expect(try edgeIsAccent())
        view.focusBorderVisible = true
        #expect(try !edgeIsAccent())
        view.focusBorderVisible = false
        #expect(try edgeIsAccent())
        view.item = .init(id: 42, app: "Test", title: "Test", frame: view.bounds, focused: false)
        #expect(try !edgeIsAccent())
    }

    @Test func hoverFocusRespectsSettingAndCurrentFocus() throws {
        let view = PlaceholderView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        var focused: [WindowID] = []
        view.actions = .init(focus: { focused.append($0) }, zoom: { _ in }, drag: { _, _ in }, drop: { _, _ in })
        view.item = .init(id: 42, app: "Test", title: "Test", frame: view.bounds, focused: false)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: 0, context: nil,
                                                   eventNumber: 0, clickCount: 0, pressure: 0))

        view.mouseEntered(with: event)
        view.mouseMoved(with: event)
        #expect(focused.isEmpty)

        view.focusFollowsMouse = true
        view.mouseEntered(with: event)
        #expect(focused == [42])

        view.item = .init(id: 42, app: "Test", title: "Test", frame: view.bounds, focused: true)
        view.mouseMoved(with: event)
        #expect(focused == [42])

        view.item = .init(id: 43, app: "Test", title: "Test", frame: view.bounds, focused: false)
        view.mouseMoved(with: event)
        #expect(focused == [42, 43])

        view.focusFollowsMouse = false
        view.mouseEntered(with: event)
        #expect(focused == [42, 43])
        view.mouseDown(with: event)
        #expect(focused == [42, 43, 43])
    }

    @Test func trackingAreaSurvivesResizeWithoutDuplicates() throws {
        let view = PlaceholderView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        view.updateTrackingAreas()
        view.frame.size = CGSize(width: 300, height: 200)
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1)
        let area = try #require(view.trackingAreas.first)
        #expect(area.options.contains([.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]))
    }
}
