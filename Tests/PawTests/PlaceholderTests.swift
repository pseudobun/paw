import AppKit
import PawCore
import Testing
@testable import paw

@MainActor
struct PlaceholderTests {
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
