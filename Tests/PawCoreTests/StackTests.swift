import CoreGraphics
import Foundation
import Testing
@testable import PawCore

struct YabaiDecodingTests {
    // Trimmed from real `yabai -m query --windows` output.
    let json = """
    [{"id":101,"pid":501,"app":"Discord","title":"#household | Lutra Labs","scratchpad":"",
      "frame":{"x":12.0000,"y":46.0000,"w":1704.0000,"h":1059.0000},"role":"AXWindow","subrole":"AXStandardWindow",
      "root-window":true,"display":1,"space":2,"level":0,"sub-level":0,"layer":"normal","sub-layer":"normal",
      "opacity":1.0000,"split-type":"none","split-child":"none","stack-index":1,"can-move":true,"can-resize":true,
      "has-focus":true,"has-shadow":true,"has-parent-zoom":false,"has-fullscreen-zoom":false,"has-ax-reference":true,
      "is-native-fullscreen":false,"is-visible":true,"is-minimized":false,"is-hidden":false,"is-floating":false,
      "is-sticky":false,"is-grabbed":false},
     {"id":102,"pid":502,"app":"Spotify","title":"Spotify Premium","frame":{"x":12.0000,"y":46.0000,"w":1704.0000,"h":1059.0000},
      "display":1,"space":2,"stack-index":2,"has-focus":false,"is-visible":false,"is-minimized":false,"is-hidden":false},
     {"id":103,"pid":503,"app":"Ghostty","title":"~","frame":{"x":12.0000,"y":46.0000,"w":850.0000,"h":1059.0000},
      "display":1,"space":2,"stack-index":0,"has-focus":false,"is-visible":true,"is-minimized":false,"is-hidden":false}]
    """

    @Test func decodesYabaiWindows() throws {
        let ws = try JSONDecoder().decode([YabaiWindow].self, from: Data(json.utf8))
        #expect(ws.count == 3)
        #expect(ws[0].app == "Discord" && ws[0].stackIndex == 1 && ws[0].hasFocus && ws[0].isVisible)
        #expect(ws[1].rect == CGRect(x: 12, y: 46, width: 1704, height: 1059))
        let spaces = try JSONDecoder().decode([YabaiSpace].self, from: Data(#"[{"index":2,"display":1,"is-visible":true,"windows":[101]}]"#.utf8))
        let stacks = StackBuilder.stacks(windows: ws, spaces: spaces)
        #expect(stacks.count == 1)
        #expect(stacks[0].items.map(\.app) == ["Discord", "Spotify"])
        #expect(stacks[0].activeIndex == 0)
        #expect(stacks[0].hasFocus)
    }
}

struct StackBuilderTests {
    let f = CGRect(x: 10, y: 40, width: 800, height: 600)

    @Test func groupsByFrameAndSpaceInStackOrder() {
        let ws = [
            YabaiWindow(id: 3, app: "C", frame: f, space: 1, stackIndex: 3),
            YabaiWindow(id: 1, app: "A", frame: f.offsetBy(dx: 2, dy: 1), space: 1, stackIndex: 1, isVisible: true),
            YabaiWindow(id: 2, app: "B", frame: f, space: 1, stackIndex: 2),
            YabaiWindow(id: 4, app: "D", frame: f, space: 2, stackIndex: 1),
            YabaiWindow(id: 5, app: "E", frame: f, space: 2, stackIndex: 2, hasFocus: true, isVisible: true),
            YabaiWindow(id: 6, app: "F", frame: f, space: 3, stackIndex: 0), // not stacked
        ]
        let spaces = [YabaiSpace(index: 1, isVisible: true), YabaiSpace(index: 2, display: 2, isVisible: true), YabaiSpace(index: 3, isVisible: true)]
        let s = StackBuilder.stacks(windows: ws, spaces: spaces)
        #expect(s.count == 2)
        #expect(s[0].items.map(\.id) == [1, 2, 3])
        #expect(s[0].activeIndex == 0 && !s[0].hasFocus)
        #expect(s[1].items.map(\.id) == [4, 5])
        #expect(s[1].activeIndex == 1 && s[1].hasFocus)
    }

    @Test func skipsHiddenSpacesMinimisedAndSingles() {
        let ws = [
            YabaiWindow(id: 1, app: "A", frame: f, space: 1, stackIndex: 1),
            YabaiWindow(id: 2, app: "B", frame: f, space: 1, stackIndex: 2, isMinimized: true),
            YabaiWindow(id: 3, app: "C", frame: f, space: 4, stackIndex: 1),
            YabaiWindow(id: 4, app: "D", frame: f, space: 4, stackIndex: 2),
        ]
        let s = StackBuilder.stacks(windows: ws, spaces: [YabaiSpace(index: 1, isVisible: true), YabaiSpace(index: 4, isVisible: false)])
        #expect(s.isEmpty)
    }

    @Test func differentFramesAreDifferentStacks() {
        let ws = [
            YabaiWindow(id: 1, app: "A", frame: f, space: 1, stackIndex: 1),
            YabaiWindow(id: 2, app: "B", frame: f, space: 1, stackIndex: 2),
            YabaiWindow(id: 3, app: "C", frame: f.offsetBy(dx: 900, dy: 0), space: 1, stackIndex: 1),
            YabaiWindow(id: 4, app: "D", frame: f.offsetBy(dx: 900, dy: 0), space: 1, stackIndex: 2),
        ]
        let s = StackBuilder.stacks(windows: ws, spaces: [YabaiSpace(index: 1, isVisible: true)])
        #expect(s.map { $0.items.map(\.id) } == [[1, 2], [3, 4]])
        #expect(s[0].key != s[1].key)
    }
}

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
