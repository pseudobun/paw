import AppKit
import PawCore
import QuartzCore
import Testing
@testable import paw

@MainActor
struct GlassTests {
    @Test func flatStyleKeepsTheThemesChrome() {
        var a = PawConfig.Appearance()
        a.glass = false
        let style = Style(a)
        #expect(!style.glass)
        #expect(style.colors == a.colors)
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
        style.decorate(l, radius: 9)
        #expect(l.backgroundColor == a.colors.island.cg)
        #expect(Double(l.borderWidth) == a.borderWidth, "\(l.borderWidth) vs \(a.borderWidth)")
        #expect(Glass.tint(of: l) == nil)
        #expect(style.cellFill(active: false) == a.colors.islandHi.withAlpha(0.5))
    }

    @Test func glassStyleLeavesTheFillToTheGlass() {
        let style = Style(PawConfig.Appearance())
        #expect(style.glass == Glass.supported)
        guard style.glass else { return }
        let l = CALayer()
        style.decorate(l, radius: 9)
        #expect(l.backgroundColor == nil)
        #expect(l.borderWidth == 0)
        #expect(l.shadowOpacity == 0)
        #expect(Glass.tint(of: l) != nil)
        #expect(Style(PawConfig.Appearance(), glass: false).glass == false, "a PNG preview is flat")
    }

    @Test func tintAndStyleFollowTheConfig() {
        guard Glass.supported else { return }
        var a = PawConfig.Appearance()
        a.glassTint = 0.5
        a.glassStyle = "clear"
        let l = CALayer()
        Style(a).decorate(l, radius: 9)
        let tint = Glass.tint(of: l)
        #expect(abs((tint?.alpha ?? 0) - a.colors.island.alpha * 0.5) < 0.01, "8-bit alpha")
        #expect(l.value(forKey: Glass.clearKey) as? Bool == true)
        if #available(macOS 26, *) {
            let host = GlassHost(content: GlassHost.layerView())
            host.adopt(l)
            #expect((host.subviews.first as? NSGlassEffectView)?.style == .clear)
        }
    }

    @Test func hostPutsGlassBehindGlassIslandsOnly() {
        guard Glass.supported else { return }
        let content = GlassHost.layerView()
        let host = GlassHost(content: content)
        host.frame = CGRect(x: 0, y: 0, width: 80, height: 30)
        let island = CALayer()
        Style(PawConfig.Appearance()).decorate(island, radius: 15)
        host.adopt(island)
        #expect(content.superview !== host, "content moves into the glass")
        if #available(macOS 26, *) {
            let glass = try? #require(host.subviews.first as? NSGlassEffectView)
            #expect(glass?.cornerRadius == 15)
            #expect(glass?.contentView === content)
            #expect(glass?.appearance?.name == .darkAqua, "OG is a dark theme")
        }
        // Same island again: the same glass view.
        let before = host.subviews.first
        host.adopt(island)
        #expect(host.subviews.first === before)

        var flat = PawConfig.Appearance()
        flat.glass = false
        let plain = CALayer()
        Style(flat).decorate(plain, radius: 15)
        host.adopt(plain)
        #expect(content.superview === host)
        #expect(host.subviews == [content])
    }

    @Test func lightThemesGetLightGlass() {
        guard #available(macOS 26, *) else { return }
        let host = GlassHost(content: GlassHost.layerView())
        let island = CALayer()
        Style(Themes.ogLight.appearance).decorate(island, radius: 9)
        host.adopt(island)
        #expect((host.subviews.first as? NSGlassEffectView)?.appearance?.name == .aqua)
    }
}
