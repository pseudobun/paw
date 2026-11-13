import AppKit
import PawCore
import QuartzCore
import Testing
@testable import paw

@MainActor
struct HUDTests {
    func appearance() -> PawConfig.Appearance {
        var a = PawConfig.Appearance()
        a.font = "system"
        // Exercise the glyph path without requiring sketchybar-app-font to be installed.
        a.appFont = "Helvetica"
        return a
    }

    func config() -> PawConfig {
        var c = PawConfig()
        c.icons.brandColors = false
        return c
    }

    @Test func alternatingIslandsReuseLayersAndHaveOnlyOneParent() throws {
        var cache = WorkspaceHUD.LayerCache()
        let style = Style(appearance())
        _ = try #require(style.appFont)
        func render(_ label: String) -> CALayer {
            cache.layer(label: label, apps: ["App"], icons: .init(), config: config(), style: style, scale: 2)
        }
        let first = render("1"), second = render("2")
        let host = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // TitlePanel.show installs each island by replacing this array.
        host.sublayers = [first]
        host.sublayers = [second]
        #expect(first.superlayer == nil)
        #expect(second.superlayer === host)
        #expect(render("1") === first)
        host.sublayers = [first]
        #expect(first.superlayer === host)
        #expect(second.superlayer == nil)
        #expect(render("2") === second)
        _ = render("3")
        #expect(render("1") !== first, "retain at most two built islands")
    }

    @Test func contentColorsGlyphsAndScaleInvalidateTheIsland() throws {
        var cache = WorkspaceHUD.LayerCache()
        let style = Style(appearance())
        _ = try #require(style.appFont)
        var c = config()
        var icons = AppIconMap(fallback: "A")
        func render(_ label: String = "1", apps: [String] = ["App"], scale: CGFloat = 2) -> CALayer {
            cache.layer(label: label, apps: apps, icons: icons, config: c, style: style, scale: scale)
        }
        let first = render()
        #expect(render() === first)
        #expect(render("2") !== first)
        #expect(render(apps: ["Other"]) !== first)
        #expect(render(apps: ["App", "Other"]) !== render(apps: ["Other", "App"]))

        let before = render()
        icons.fallback = "B"
        let fallback = render()
        #expect(fallback !== before)
        icons.prefix = [("Ap", "C")]
        let prefix = render()
        #expect(prefix !== fallback)
        icons = icons.merging(["App": "D"])
        let exact = render()
        #expect(exact !== prefix)
        c.icons.colors["App"] = ARGB(0xffff0000)
        let red = render()
        #expect(red !== exact)
        c.icons.colors["App"] = ARGB(0xff0000ff)
        let blue = render()
        #expect(blue !== red)
        c.icons.brandColors = true
        #expect(render() === blue, "an explicit color still wins over brand color lookup")
        c.icons.brandColors = false
        c.icons.colors.removeAll()
        let uncolored = render()
        #expect(uncolored !== blue)
        let scaled = render(scale: 1)
        #expect(scaled !== uncolored)
        #expect(scaled.contentsScale == 1)
        #expect(scaled.sublayers?.first?.sublayers?.allSatisfy { $0.contentsScale == 1 } == true)
    }

    @Test func appearanceChangesInvalidateTheIsland() throws {
        var cache = WorkspaceHUD.LayerCache()
        var a = appearance()
        let changes: [(inout PawConfig.Appearance) -> Void] = [
            { $0.font = "system-mono" }, { $0.fontSize += 1 },
            { $0.fontWeight = "regular" }, { $0.boldWeight = "bold" },
            { $0.appFont = "Times-Roman" }, { $0.appIconSize += 1 },
            { $0.radius += 1 }, { $0.borderWidth += 1 },
            { $0.shadow.toggle() }, { $0.shadowOpacity += 0.1 }, { $0.shadowRadius += 1 },
            { $0.islandHeight += 1 }, { $0.pills.toggle() },
            { $0.colors.island = ARGB(0xff112233) }, { $0.colors.border = ARGB(0xff223344) },
            { $0.colors.fg = ARGB(0xff334455) }, { $0.colors.accent = ARGB(0xff445566) },
        ]
        func render() throws -> CALayer {
            let style = Style(a)
            _ = try #require(style.appFont)
            return cache.layer(label: "1", apps: ["App"], icons: .init(), config: config(), style: style, scale: 2)
        }
        var previous = try render()
        for change in changes {
            change(&a)
            let next = try render()
            #expect(next !== previous)
            #expect(try render() === next)
            previous = next
        }
    }

    @Test func imageFallbacksAreRebuiltButEmptyIslandsCanBeReused() {
        var cache = WorkspaceHUD.LayerCache()
        var a = appearance()
        a.appFont = "PAW-test-font-that-does-not-exist"
        let style = Style(a)
        #expect(style.appFont == nil)
        func render(_ apps: [String]) -> CALayer {
            cache.layer(label: "1", apps: apps, icons: .init(), config: config(), style: style, scale: 2)
        }
        // An empty app name avoids looking up any installed/running applications.
        #expect(render([""]) !== render([""]))
        #expect(render([]) === render([]))
    }
}
