import CoreGraphics
import Foundation
import Testing
@testable import PawCore

struct LayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let m = IndicatorLayout.Metrics(width: 28, cellHeight: 22, gap: 2, padding: 3, offsetX: 4, offsetY: 2)

    @Test func sideFollowsStackline() {
        let left = CGRect(x: 12, y: 46, width: 850, height: 1000)
        let right = CGRect(x: 870, y: 46, width: 846, height: 1000)
        let full = CGRect(x: 12, y: 46, width: 1704, height: 1000)
        #expect(IndicatorLayout.resolve(.auto, window: left, screen: screen) == .left)
        #expect(IndicatorLayout.resolve(.auto, window: right, screen: screen) == .right)
        #expect(IndicatorLayout.resolve(.auto, window: full, screen: screen) == .left)
        #expect(IndicatorLayout.resolve(.right, window: left, screen: screen) == .right)
    }

    @Test func frameNextToWindowAndOnScreen() {
        let (r, side) = IndicatorLayout.frame(window: CGRect(x: 40, y: 46, width: 800, height: 900), screen: screen, count: 3, side: .auto, metrics: m)
        #expect(side == .left)
        #expect(r == CGRect(x: 8, y: 48, width: 28, height: 3 * 2 + 3 * 22 + 2 * 2))
        // Window at the screen edge: the island stays on screen.
        let (edge, _) = IndicatorLayout.frame(window: CGRect(x: 2, y: 46, width: 800, height: 900), screen: screen, count: 2, side: .left, metrics: m)
        #expect(edge.minX == 0)
        let (r2, s2) = IndicatorLayout.frame(window: CGRect(x: 900, y: 46, width: 826, height: 900), screen: screen, count: 2, side: .auto, metrics: m)
        #expect(s2 == .right)
        #expect(r2.maxX == screen.maxX)
        let (inside, _) = IndicatorLayout.frame(window: CGRect(x: 100, y: 100, width: 500, height: 500), screen: screen, count: 2, side: .insideRight, metrics: m)
        #expect(inside.minX == CGFloat(568))
    }

    @Test func secondScreenNegativeCoordinates() {
        let ext = CGRect(x: -2560, y: -1440, width: 2560, height: 1440)
        let (r, _) = IndicatorLayout.frame(window: CGRect(x: -2550, y: -1400, width: 1200, height: 900), screen: ext, count: 2, side: .auto, metrics: m)
        #expect(r.minX == -2560)
        #expect(r.minY == -1398)
    }

    @Test func cellsAndHitTesting() {
        #expect(IndicatorLayout.cell(1, metrics: m) == CGRect(x: 3, y: 27, width: 22, height: 22))
        #expect(IndicatorLayout.cellIndex(at: CGPoint(x: 14, y: 10), count: 3, metrics: m) == 0)
        #expect(IndicatorLayout.cellIndex(at: CGPoint(x: 14, y: 30), count: 3, metrics: m) == 1)
        #expect(IndicatorLayout.cellIndex(at: CGPoint(x: 14, y: 200), count: 3, metrics: m) == nil)
    }
}

struct GeometryTests {
    @Test func axCocoaRoundTrip() {
        let ax = CGRect(x: 100, y: 50, width: 80, height: 20)
        let cocoa = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: 1117)
        #expect(cocoa == CGRect(x: 100, y: 1047, width: 80, height: 20))
        #expect(ScreenGeometry.ax(fromCocoa: cocoa, primaryHeight: 1117) == ax)
        #expect(ScreenGeometry.axFrame(ofScreen: CGRect(x: -2560, y: 1117, width: 2560, height: 1440), primaryHeight: 1117)
                == CGRect(x: -2560, y: -1440, width: 2560, height: 1440))
    }

    @Test func screenForRect() {
        let screens = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1728, y: -300, width: 2560, height: 1440)]
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 10, y: 10, width: 5, height: 5), screens: screens) == 0)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 1700, y: 10, width: 100, height: 5), screens: screens) == 1)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 9000, y: 10, width: 5, height: 5), screens: screens) == 1)
    }
}

struct ColorTests {
    @Test func parsesSketchybarAndCSS() {
        #expect(ARGB.parse("0xeb1d1d16") == ARGB(0xeb1d_1d16))
        #expect(ARGB.parse("0x1d1d16") == ARGB(0xff1d_1d16))
        #expect(ARGB.parse("#ead186") == ARGB(0xffea_d186))
        #expect(ARGB.parse("#ead18680") == ARGB(0x80ea_d186))
        #expect(ARGB.parse("nope") == nil)
        #expect(ARGB(0xeb1d_1d16).withAlpha(1).value == 0xff1d_1d16)
    }
}

struct IconTests {
    @Test func bundledMapMatchesSketchybar() {
        let m = AppIconMap.bundled
        #expect(m.exact.count > 500)
        #expect(m.glyph(for: "Discord") == ":discord:")
        #expect(m.glyph(for: "Spotify") == ":spotify:")
        #expect(m.glyph(for: "Adobe Photoshop 2026") == ":photoshop:")
        #expect(m.glyph(for: "Some Unknown App") == ":default:")
        #expect(m.mapped("Some Unknown App") == nil)
        #expect(m.mapped("Adobe Photoshop 2026") == ":photoshop:")
    }

    @Test func parsesLuaWithEscapes() {
        let lua = """
        local M = { exact = {
          ["Foo \\"Bar\\""] = ":foo:",
          ["Zed"] = ":zed:",
        }, prefix = {
          { "Adobe X", ":x:" },
        }, default = ":def:" }
        """
        let m = AppIconMap.parse(lua: lua)
        #expect(m.glyph(for: "Foo \"Bar\"") == ":foo:")
        #expect(m.glyph(for: "Adobe X 2") == ":x:")
        #expect(m.glyph(for: "nope") == ":def:")
        #expect(m.merging(["Zed": ":code:"]).glyph(for: "Zed") == ":code:")
    }
}

struct BrandColorTests {
    func pixels(_ list: [(UInt8, UInt8, UInt8, Int)]) -> [UInt8] {
        list.flatMap { p in (0..<p.3).flatMap { _ in [p.0, p.1, p.2, 255] } }
    }

    @Test func picksTheMainHueOverWhiteAndBlack() {
        let c = BrandColor.pick(rgba: pixels([(30, 215, 96, 300), (255, 255, 255, 400), (0, 0, 0, 300)]))
        #expect(c != nil && c!.green > c!.red && c!.green > c!.blue)
    }

    @Test func greyIconsHaveNoColour() {
        #expect(BrandColor.pick(rgba: pixels([(128, 128, 128, 500), (240, 240, 240, 500)])) == nil)
    }

    @Test func darkBlueIsLiftedToReadOnDark() {
        let c = BrandColor.pick(rgba: pixels([(20, 30, 200, 500)]))!
        #expect(0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue >= 0.4)
    }
}
