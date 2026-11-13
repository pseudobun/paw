import AppKit
import PawCore
import Testing
@testable import paw

@MainActor
struct OverviewReuseTests {
    /// No windows, screens, application, or accessibility access needed.
    @Test func panelReuseRequiresTheSameEnvironment() {
        typealias Environment = OverviewPanel.Environment
        let screen = Environment.Screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), scale: 2)
        let original = Environment(config: PawConfig(), style: PawConfig.Appearance(),
                                   appearance: "NSAppearanceNameAqua", keyDisplay: 0, screens: [screen])
        let unchanged = Environment(config: PawConfig(), style: PawConfig.Appearance(),
                                    appearance: "NSAppearanceNameAqua", keyDisplay: 0, screens: [screen])
        #expect(original == unchanged)

        let changes: [(String, (inout Environment) -> Void)] = [
            ("config reload", { $0.config.layout.gap += 1 }),
            ("thumbnails", { $0.config.overview.thumbnails = "off" }),
            ("configured appearance", { $0.config.appearance.fontSize += 1 }),
            ("resolved style", { $0.style.fontSize += 1 }),
            ("system appearance", { $0.appearance = "NSAppearanceNameDarkAqua" }),
            ("search display", { $0.keyDisplay = 1 }),
            ("display identity", { $0.screens[0].id = 2 }),
            ("display position", { $0.screens[0].frame.origin.x = 1440 }),
            ("display size", { $0.screens[0].frame.size.width = 1920 }),
            ("menu bar or Dock", { $0.screens[0].visibleFrame.size.height -= 25 }),
            ("backing scale", { $0.screens[0].scale = 1 }),
            ("display removed", { $0.screens = [] }),
            ("display added", { $0.screens.append(screen) }),
        ]
        for (reason, change) in changes {
            var changed = original
            change(&changed)
            #expect(changed != original, "Rebuild after changing \(reason)")
        }
        var twoDisplays = original
        var other = screen
        other.id = 2
        twoDisplays.screens.append(other)
        var reordered = twoDisplays
        reordered.screens.reverse()
        #expect(reordered != twoDisplays, "Display indices must still identify the same screens")
    }
}
