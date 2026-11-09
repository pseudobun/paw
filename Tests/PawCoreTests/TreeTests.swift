import CoreGraphics
import Foundation
import Testing
@testable import PawCore

struct TreeTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func bsp(_ ids: [WindowID]) -> Workspace {
        let ws = Workspace(name: "1", layout: .bsp)
        for id in ids {
            ws.insert(id, area: area)
            ws.focused = id
        }
        return ws
    }

    func frames(_ ws: Workspace, gap: Double = 0) -> [WindowID: CGRect] { TreeLayout.windowFrames(ws, in: area, gap: gap) }

    @Test func bspSplitsWideTilesSideBySide() {
        let ws = bsp([1, 2])
        #expect(frames(ws) == [1: CGRect(x: 0, y: 0, width: 500, height: 600), 2: CGRect(x: 500, y: 0, width: 500, height: 600)])
        ws.insert(3, area: area) // focused is 2 (500×600, tall) → splits top/bottom
        #expect(frames(ws)[2] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(frames(ws)[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func gapsBetweenTiles() {
        let f = frames(bsp([1, 2]), gap: 10)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 495, height: 600))
        #expect(f[2] == CGRect(x: 505, y: 0, width: 495, height: 600))
    }

    @Test func removeCollapsesSibling() {
        let ws = bsp([1, 2, 3])
        ws.remove(2)
        #expect(frames(ws)[3] == CGRect(x: 500, y: 0, width: 500, height: 600))
        ws.remove(1)
        #expect(frames(ws)[3] == area)
        ws.remove(3)
        #expect(ws.root == nil && ws.isEmpty)
    }

    @Test func stackLayoutKeepsOneTile() {
        let ws = Workspace(name: "s", layout: .stack)
        for id: WindowID in [1, 2, 3] { ws.insert(id, area: area) }
        #expect(ws.tiles.count == 1)
        #expect(frames(ws).values.allSatisfy { $0 == area })
        #expect(ws.tiles[0].activeWindow == 3)
        ws.setLayout(.bsp, area: area)
        #expect(ws.tiles.count == 3)
        ws.setLayout(.stack, area: area)
        #expect(ws.tiles.count == 1 && ws.tiledWindows.sorted() == [1, 2, 3])
    }

    @Test func focusNeighbours() {
        let ws = bsp([1, 2, 3]) // 1 left, 2 top-right, 3 bottom-right
        let t1 = ws.tile(of: 1)!, t2 = ws.tile(of: 2)!, t3 = ws.tile(of: 3)!
        #expect(ws.neighbor(of: t1, .east, area: area) === t2) // equal distance, t2 first by centre tie → top
        #expect(ws.neighbor(of: t3, .west, area: area) === t1)
        #expect(ws.neighbor(of: t2, .south, area: area) === t3)
        #expect(ws.neighbor(of: t3, .north, area: area) === t2)
        #expect(ws.neighbor(of: t1, .west, area: area) == nil)
    }

    @Test func swapExchangesPlaces() {
        let ws = bsp([1, 2])
        #expect(ws.swap(1, .east, area: area))
        #expect(frames(ws)[1]!.minX == 500 && frames(ws)[2]!.minX == 0)
        #expect(!ws.swap(1, .east, area: area))
    }

    @Test func stackMergesAndUnstackSplits() {
        let ws = bsp([1, 2, 3])
        #expect(ws.stack(3, .north, area: area)) // 3 joins 2's stack
        #expect(ws.tiles.count == 2)
        #expect(ws.tile(of: 2)!.windows == [2, 3])
        #expect(frames(ws)[3] == CGRect(x: 500, y: 0, width: 500, height: 600))
        #expect(ws.stack(1, .east, area: area)) // all in one stack
        #expect(ws.tiles.count == 1 && ws.tiles[0].windows == [2, 3, 1])
        #expect(ws.unstack(3, area: area))
        #expect(ws.tiles.count == 2)
        #expect(!ws.unstack(3, area: area))
        ws.unstackAll(2, area: area)
        #expect(ws.tiles.count == 3)
    }

    @Test func cycleStackWraps() {
        let ws = Workspace(name: "s", layout: .stack)
        for id: WindowID in [1, 2, 3] { ws.insert(id, area: area) }
        #expect(ws.cycleStack(3, by: 1) == 1)
        #expect(ws.cycleStack(1, by: -1) == 3)
        ws.activate(2)
        #expect(ws.tiles[0].activeWindow == 2)
    }

    @Test func warpMovesToThatSide() {
        let ws = bsp([1, 2, 3]) // 1 | (2 / 3)
        #expect(ws.warp(1, .east, area: area))
        // 1 split 2's tile, now on its east side.
        let f = frames(ws)
        #expect(f[1]!.minX > f[2]!.minX)
        #expect(f[3]!.width == 1000) // 3 took the bottom row after 1 left
        let two = bsp([1, 2])
        #expect(two.warp(2, .west, area: area))
        #expect(frames(two)[2]!.minX == 0)
    }

    @Test func resizeMovesTheRightDivider() {
        let ws = bsp([1, 2])
        #expect(ws.resize(1, .east, by: 100, area: area))
        #expect(frames(ws)[1]!.width == 600)
        #expect(ws.resize(2, .west, by: 100, area: area))
        #expect(frames(ws)[2]!.width == 500)
        #expect(!ws.resize(1, .west, by: 100, area: area)) // no divider on the left
    }

    @Test func rotateAndBalance() {
        let ws = bsp([1, 2])
        ws.rotate(90)
        #expect(frames(ws)[1] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        ws.rotate(270)
        #expect(frames(ws)[1]!.minX == 0 && frames(ws)[1]!.height == 600)
        ws.rotate(180)
        #expect(frames(ws)[2]!.minX == 0)
        _ = ws.resize(2, .east, by: 200, area: area)
        ws.balance()
        #expect(frames(ws)[2]!.width == 500)
    }

    @Test func floatAndZoom() {
        let ws = bsp([1, 2])
        ws.toggleFloat(2, area: area)
        #expect(ws.isFloating(2) && frames(ws)[1] == area && frames(ws)[2] == nil)
        ws.toggleFloat(2, area: area)
        #expect(!ws.isFloating(2) && ws.tiles.count == 2)
        ws.toggleZoom(1)
        #expect(frames(ws)[1] == area)
        ws.toggleZoom(1)
        #expect(frames(ws)[1]!.width == 500)
        ws.toggleSplit(1)
        #expect(frames(ws)[1]!.height == 300)
    }

    @Test func arrangeFromPreset() {
        let ws = Workspace(name: "1", layout: .bsp)
        let preset = WorkspacePreset(layout: .bsp, tiles: [.init(apps: ["Discord", "Spotify"]), .init(apps: ["/^Ghost/"], size: 3), .init(apps: ["Mail"])])
        let windows: [(id: WindowID, app: String)] = [(1, "Ghostty"), (2, "Spotify"), (3, "Discord"), (4, "Safari")]
        for w in windows { ws.insert(w.id, area: area) }
        ws.arrange(preset, windows: windows, area: area)
        let t0 = ws.tiles.first { $0.slot == 0 }!
        #expect(t0.windows == [3, 2]) // apps order: Discord then Spotify
        let f = frames(ws)
        #expect(f[3]!.width == 250 && f[1]!.minX == 250) // 1:3 → 250 / 750; Mail's tile is empty, so absent
        #expect(f[4] != nil) // Safari isn't in the preset but still tiled
        // A new Spotify window lands in slot 0.
        ws.insert(5, area: area, slot: preset.slot(for: "Spotify"))
        #expect(ws.tile(of: 5) === t0)
    }

    @Test func stackPresetIsOneStack() {
        let ws = Workspace(name: "2", layout: .bsp)
        let preset = WorkspacePreset(layout: .stack, tiles: [.init(apps: ["Safari"]), .init(apps: ["Zed"])])
        ws.arrange(preset, windows: [(1, "Zed"), (2, "Safari")], area: area)
        #expect(ws.tiles.count == 1 && ws.tiles[0].windows == [2, 1])
    }

    @Test func areaRespectsBarAndMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let pad = Padding(top: 2, bottom: 2, left: 24, right: 24)
        // Hidden menu bar: the 41 pt bar is all ours to skip.
        #expect(TreeLayout.area(screen: screen, visible: screen, barTop: 41, barBottom: 0, padding: pad)
                == CGRect(x: 24, y: 43, width: 1680, height: 1117 - 43 - 2))
        // Visible 37 pt menu bar: only 4 more for the bar.
        let vis = CGRect(x: 0, y: 37, width: 1728, height: 1080)
        #expect(TreeLayout.area(screen: screen, visible: vis, barTop: 41, barBottom: 0, padding: pad).minY == CGFloat(43))
    }
}

struct CommandTests {
    @Test func parsesEverything() throws {
        #expect(try Command.parse("focus left") == .focus(.dir(.west)))
        #expect(try Command.parse("focus stack.next") == .focus(.stackNext))
        #expect(try Command.parse("swap east") == .swap(.east))
        #expect(try Command.parse("stack north") == .stack(.north))
        #expect(try Command.parse("unstack all") == .unstack(all: true))
        #expect(try Command.parse("layout stack") == .layout(.stack))
        #expect(try Command.parse("toggle zoom") == .toggle(.zoom))
        #expect(try Command.parse("rotate 270") == .rotate(270))
        #expect(try Command.parse("resize west -40") == .resize(.west, -40))
        #expect(try Command.parse("workspace 3") == .workspace(.name("3")))
        #expect(try Command.parse("workspace new") == .workspaceNew)
        #expect(try Command.parse("move-to 4 --follow") == .moveTo(.name("4"), follow: true))
        #expect(try Command.parse("move-to next") == .moveTo(.next, follow: false))
        #expect(try Command.parse("display 2") == .focusDisplay(.index(2)))
        #expect(try Command.parse("exec open -a 'Alacritty'") == .exec("open -a 'Alacritty'"))
        #expect(try Command.parse("mode resize") == .mode("resize"))
        #expect(try Command.parse("mode exit") == .mode(nil))
        #expect(try Command.parseAll("toggle float; grid 4:4:1:1:2:2").count == 2)
        #expect(throws: ConfigProblem.self) { try Command.parse("focus sideways") }
        #expect(throws: ConfigProblem.self) { try Command.parse("teleport") }
        #expect(throws: ConfigProblem.self) { try Command.parse("grid 1:2:3") }
    }

    @Test func gridFrame() throws {
        guard case .grid(let g) = try Command.parse("grid 4:4:1:1:2:2") else { Issue.record("no grid"); return }
        #expect(g.frame(in: CGRect(x: 0, y: 0, width: 800, height: 400)) == CGRect(x: 200, y: 100, width: 400, height: 200))
    }

    @Test func everyDefaultBindingParses() throws {
        for (key, cmd) in Defaults.bindings {
            #expect(KeySpec.parse(key) != nil, "\(key)")
            _ = try Command.parseAll(cmd)
        }
    }
}

struct KeySpecTests {
    let cmd: UInt64 = 0x100000, ctrl: UInt64 = 0x40000, alt: UInt64 = 0x80000, shift: UInt64 = 0x20000, fn: UInt64 = 0x800000

    @Test func matchesModifiersExactly() throws {
        let s = try #require(KeySpec.parse("ctrl+alt+left"))
        #expect(s.matches(keyCode: 0x7B, flags: ctrl | alt | fn)) // arrows carry fn
        #expect(!s.matches(keyCode: 0x7B, flags: ctrl | alt | shift))
        #expect(!s.matches(keyCode: 0x7B, flags: ctrl))
        let h = try #require(KeySpec.parse("hyper+0x18"))
        #expect(h.keyCode == 0x18 && h.mods == .hyper)
    }

    @Test func rightAltNeedsRightAlt() throws {
        let s = try #require(KeySpec.parse("ralt+1"))
        #expect(s.matches(keyCode: 0x12, flags: alt | 0x40))
        #expect(!s.matches(keyCode: 0x12, flags: alt | 0x20))
        let any = try #require(KeySpec.parse("alt+1"))
        #expect(any.matches(keyCode: 0x12, flags: alt | 0x20))
    }

    @Test func rejectsNonsense() {
        #expect(KeySpec.parse("ctrl+banana") == nil)
        #expect(KeySpec.parse("super+a") == nil)
    }
}

struct EasingTests {
    @Test func endsAndMonotonic() {
        for e in Easing.allCases {
            #expect(abs(e.value(0)) < 0.01, "\(e)")
            #expect(abs(e.value(1) - 1) < 0.01, "\(e)")
        }
        #expect(Easing.easeOutCubic.value(0.5) > 0.5)
        #expect(Easing.lerp(CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 200, height: 100), 0.5)
                == CGRect(x: 50, y: 0, width: 150, height: 100))
    }
}
