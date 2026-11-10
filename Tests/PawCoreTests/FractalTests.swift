import CoreGraphics
import Foundation
import Testing
@testable import PawCore

/// The weighted n-ary tree (TrellisWM's model), drop zones, undo snapshots and anchors.
struct FractalTests {
    let area = CGRect(x: 0, y: 0, width: 1200, height: 600)

    func frames(_ ws: Workspace, gap: Double = 0) -> [WindowID: CGRect] { TreeLayout.windowFrames(ws, in: area, gap: gap) }

    func columns(_ ids: [WindowID]) -> Workspace {
        let ws = Workspace(name: "c", layout: .columns)
        for id in ids { ws.insert(id, area: area); ws.focused = id }
        return ws
    }

    @Test func columnsAreEqualAndFlat() {
        let ws = columns([1, 2, 3])
        #expect(ws.root?.children.count == 3)
        #expect(frames(ws)[1]!.width == 400 && frames(ws)[2]!.minX == 400 && frames(ws)[3]!.minX == 800)
        ws.remove(2)
        // The removed column's width goes to the one before it; the last keeps its size.
        #expect(frames(ws)[1]!.width == 800 && frames(ws)[3]!.width == 400)
    }

    @Test func masterKeepsOneBigWindow() {
        let ws = Workspace(name: "m", layout: .master)
        for id: WindowID in [1, 2, 3] { ws.insert(id, area: area); ws.focused = id }
        let f = frames(ws)
        #expect(abs(f[1]!.width - 1200 * 0.62) <= 1 && f[1]!.height == 600)
        #expect(f[2]!.minX == f[3]!.minX && f[2]!.height == 300 && f[3]!.minY == 300)
    }

    @Test func splittingAlongTheSameAxisAddsASibling() {
        let ws = Workspace(name: "b", layout: .bsp)
        ws.insert(1, area: area); ws.focused = 1
        ws.insert(2, area: area) // 1 | 2
        #expect(ws.warp(1, .east, area: area) || true)
        ws.focused = 2
        // Unstacking sideways in a row of tiles adds a third column, not a nested split.
        ws.tile(of: 2)!.windows.append(3)
        #expect(ws.unstack(3, area: area, toward: .east))
        #expect(ws.root?.children.count == 3 && ws.root?.axis == .horizontal)
    }

    @Test func gapsAddUpExactly() {
        let ws = columns([1, 2, 3])
        let f = frames(ws, gap: 10)
        #expect(f[1]!.minX == 0 && f[3]!.maxX == 1200)
        #expect(f[2]!.minX == f[1]!.maxX + 10 && f[3]!.minX == f[2]!.maxX + 10)
    }

    @Test func seamsPushNeighboursAlong() {
        let ws = columns([1, 2, 3])
        let p = ws.root!
        // Grow column 1 by half the width: column 2 gives way down to its minimum, then 3.
        ws.moveSeam(p, 0, by: 0.5)
        let f = p.fractions
        #expect(abs(f[0] - (1.0 / 3 + 0.5)) < 1e-9)
        #expect(abs(f[1] - Workspace.minFraction) < 1e-9)
        #expect(abs(f.reduce(0, +) - 1) < 1e-9)
        ws.setSeam(p, 0, at: 0.25)
        #expect(abs(p.fractions[0] - 0.25) < 1e-9)
        ws.equalizeSeam(p, 0)
        #expect(abs(p.weights[0] - p.weights[1]) < 1e-9)
    }

    @Test func resizeCascades() {
        let ws = columns([1, 2, 3])
        #expect(ws.resize(1, .east, by: 700, area: area))
        let f = frames(ws)
        #expect(f[1]!.width >= 1050) // 400 + 340 from 2 (down to 5%) + 360 from 3, capped at 3's minimum
        #expect(f[2]!.width >= 59 && f[3]!.width >= 59)
        #expect(!ws.resize(1, .west, by: 50, area: area))
    }

    @Test func seamGeometry() {
        let ws = columns([1, 2])
        let s = TreeLayout.seams(ws, in: area, gap: 10)
        #expect(s.count == 1 && s[0].frame == CGRect(x: 595, y: 0, width: 10, height: 600) && s[0].axis == .horizontal)
    }

    // MARK: Drops

    @Test func dropOnAnEdgeSplitsThatTile() {
        let ws = columns([1, 2, 3])
        #expect(ws.move(3, to: .split(tile: 1, side: .south), area: area))
        let f = frames(ws)
        #expect(f[1]!.minX == f[3]!.minX && f[3]!.minY > f[1]!.minY)
        #expect(ws.tiles.count == 3)
    }

    @Test func dropOnASeamMakesEqualRoom() {
        let ws = columns([1, 2, 3])
        ws.moveSeam(ws.root!, 0, by: 0.2)
        #expect(ws.move(3, to: .seam(before: 1, after: 2, axis: .horizontal), area: area))
        let order = ws.root!.children.map { $0.windows }
        #expect(order == [[1], [3], [2]])
        #expect(Set(ws.root!.weights).count == 1)
    }

    @Test func dropAtTheEdgeDocksBesideEverything() {
        let ws = Workspace(name: "e", layout: .bsp)
        for id: WindowID in [1, 2] { ws.insert(id, area: area); ws.focused = id }
        #expect(ws.move(2, to: .edge(.south), area: area))
        #expect(ws.move(3, to: .edge(.north), area: area))
        let f = frames(ws)
        #expect(f[3]!.minY == 0 && f[3]!.width == 1200 && f[2]!.maxY == 600 && f[2]!.width == 1200)
    }

    @Test func dropInTheMiddleSwapsOrStacks() {
        let ws = columns([1, 2])
        #expect(ws.move(1, to: .swap(tile: 2), area: area))
        #expect(frames(ws)[1]!.minX == 600)
        #expect(ws.move(1, to: .stack(tile: 2), area: area))
        #expect(ws.tiles.count == 1 && ws.tiles[0].windows == [2, 1])
        #expect(!ws.move(1, to: .stack(tile: 2), area: area))
    }

    @Test func zonesUnderThePointer() {
        let ws = columns([1, 2])
        func at(_ x: Double, _ y: Double, _ id: WindowID = 2, stack: Bool = false) -> DropTarget? {
            DropZones.target(at: CGPoint(x: x, y: y), in: ws, area: area, gap: 10, dragging: id, stack: stack)
        }
        #expect(at(300, 300) == .swap(tile: 1))
        #expect(at(300, 300, stack: true) == .stack(tile: 1))
        #expect(at(300, 20) == .split(tile: 1, side: .north))
        #expect(at(20, 300) == .split(tile: 1, side: .west))
        #expect(at(900, 300) == nil) // its own lone tile
        #expect(at(600, 300) == nil) // the seam next to its own tile
        #expect(at(1199, 300) == .edge(.east))
        let three = columns([1, 2, 3])
        #expect(DropZones.target(at: CGPoint(x: 400, y: 300), in: three, area: area, gap: 10, dragging: 3, stack: false)
            == .seam(before: 1, after: 2, axis: .horizontal))
        let p = DropZones.preview(.split(tile: 1, side: .north), in: ws, area: area, gap: 0, dragging: 2)
        #expect(p == CGRect(x: 0, y: 0, width: 1200, height: 300))
        #expect(ws.tiles.count == 2) // the preview didn't touch the real tree
    }

    // MARK: Undo and restarts

    @Test func snapshotsRestoreTheTree() {
        let ws = columns([1, 2, 3])
        ws.moveSeam(ws.root!, 1, by: 0.1)
        let snap = ws.snapshot()
        let before = frames(ws)
        ws.balance()
        ws.rotate(90)
        ws.restore(snap, area: area)
        #expect(frames(ws) == before)
        // Survives JSON (paw's state file).
        let data = try! JSONEncoder().encode(snap)
        #expect(try! JSONDecoder().decode(WorkspaceSnapshot.self, from: data) == snap)
    }

    @Test func restoreSkipsGoneWindowsAndKeepsNewOnes() {
        let ws = columns([1, 2, 3])
        let snap = ws.snapshot()
        ws.remove(2)
        ws.insert(4, area: area)
        ws.restore(snap, area: area)
        #expect(Set(ws.tiledWindows) == [1, 3, 4])
        #expect(ws.tile(of: 2) == nil)
    }

    @Test func anchorsPutAWindowBack() {
        let ws = columns([1, 2, 3])
        ws.moveSeam(ws.root!, 0, by: 0.1)
        let before = frames(ws)
        let a = ws.anchor(of: 2)!
        ws.remove(2)
        #expect(ws.insert(2, at: a))
        let after = frames(ws)
        for id: WindowID in [1, 2, 3] { #expect(abs(after[id]!.minX - before[id]!.minX) <= 1 && abs(after[id]!.width - before[id]!.width) <= 1) }
        // A stacked window goes back into its stack.
        ws.tile(of: 1)!.windows.append(5)
        let s = ws.anchor(of: 5)!
        ws.remove(5)
        #expect(ws.insert(5, at: s) && ws.tile(of: 1)!.windows == [1, 5])
    }

    // MARK: Zoom

    @Test func zoomStepsThroughTheTree() {
        let ws = columns([1, 2])
        ws.layout = .bsp
        #expect(ws.move(3, to: .split(tile: 2, side: .south), area: area)) // 1 | (2 / 3)
        #expect(ws.zoomIn(toward: 2))
        var f = frames(ws)
        #expect(f[1] == nil && f[2] == CGRect(x: 0, y: 0, width: 1200, height: 300) && f[3]!.width == 1200)
        #expect(ws.zoomIn(toward: 2))
        f = frames(ws)
        #expect(f[2] == area && f[3] == nil)
        #expect(!ws.zoomIn(toward: 2))
        #expect(ws.zoomDepth(of: 2) == (2, 2))
        #expect(ws.zoomOut() && ws.zoomOut() && !ws.zoomOut())
        #expect(frames(ws).count == 3)
        // The shown branch disappearing shows everything again.
        #expect(ws.zoomIn(toward: 3) && ws.zoomIn(toward: 3))
        ws.remove(3)
        #expect(frames(ws).count == 2)
    }

    // MARK: Canvas

    @Test func canvasKeepsTilesBigAndFollowsFocus() {
        let ws = Workspace(name: "c", layout: .bsp)
        ws.canvasMin = CGSize(width: 500, height: 300)
        // 1200×600: two tiles fit side by side, a third doesn't (3 × 500 > 1200).
        ws.insert(1, area: area); ws.focused = 1
        ws.insert(2, area: area); ws.focused = 2
        #expect(TreeLayout.canvas(ws, in: area, gap: 0) == area)
        #expect(ws.move(3, to: .edge(.east), area: area)) // 1 | 2 | 3 at ⅓ each would be 400 wide
        let canvas = TreeLayout.canvas(ws, in: area, gap: 0)
        #expect(canvas.width >= 1500 && canvas.height == 600)
        ws.focused = 3
        #expect(ws.frameCamera(on: 3, area: area, gap: 0))
        let shown = TreeLayout.windowFrames(ws, in: area, gap: 0)
        #expect(shown[3] == area && shown.count == 1)
        // Full frames: the whole canvas, every tile at least the minimum.
        let full = TreeLayout.windowFrames(ws, in: area, gap: 0, full: true)
        #expect(full.count == 3 && full.values.allSatisfy { $0.width >= 499 })
        // Focus to the west, off screen: the neighbour is found in the whole tree.
        let west = ws.neighbor(of: ws.tile(of: 3)!, .west, area: area)
        #expect(west?.windows == [2])
        #expect(ws.frameCamera(on: 2, area: area, gap: 0))
        #expect(TreeLayout.windowFrames(ws, in: area, gap: 0)[2] != nil)
        // A zoom out by hand stays while focus is inside it.
        #expect(ws.zoomOut() || ws.zoomOut())
        #expect(!ws.frameCamera(on: 2, area: area, gap: 0))
    }

    @Test func cameraFramesPutHiddenWindowsOffScreen() {
        let ws = columns([1, 2])
        ws.layout = .bsp
        #expect(ws.zoomIn(toward: 2))
        let f = TreeLayout.cameraFrames(ws, in: area, gap: 0)
        #expect(f[2] == area)
        #expect(f[1] == CGRect(x: -1200, y: 0, width: 1200, height: 600)) // just left of the screen
    }

    @Test func resizeStopsAtTheMinimum() {
        let ws = columns([1, 2])
        ws.layout = .bsp
        ws.canvasMin = CGSize(width: 400, height: 200)
        #expect(ws.resize(1, .east, by: 500, area: area))
        #expect(frames(ws)[2]!.width == 400) // 2 stops at its minimum, 1 gets the rest
        #expect(ws.view == nil)
    }

    @Test func resizeStopsAtAPlaceholdersMinimum() {
        let ws = columns([1, 2])
        ws.layout = .bsp
        ws.placeholderMin = CGSize(width: 160, height: 120)
        #expect(ws.resize(1, .east, by: 1000, area: area))
        #expect(frames(ws)[2]!.width == 160) // a placeholder, but no smaller
        // Placeholders off: no floor beyond the usual share.
        let off = columns([1, 2])
        off.layout = .bsp
        off.windowMins[2] = CGSize(width: 700, height: 300)
        #expect(off.resize(1, .east, by: 1000, area: area))
        #expect(frames(off)[2]!.width < 160)
    }

    @Test func regionShowsOnlyThePickedNeighbours() {
        let ws = columns([1, 2, 3])
        ws.layout = .bsp
        #expect(ws.setView(containing: [2, 3]))
        let f = frames(ws)
        #expect(f[1] == nil && f[2]!.minX == 0 && f[3]!.maxX == 1200 && abs(f[2]!.width - 600) <= 1)
        #expect(ws.shownWindows == [2, 3])
        // Zooming out shows the whole branch again.
        #expect(ws.zoomOut())
        #expect(frames(ws).count == 3)
        // Focus outside the region ends it.
        #expect(ws.setView(containing: [2, 3]))
        #expect(ws.frameCamera(on: 1, area: area, gap: 0))
        #expect(frames(ws).count == 3)
    }

    @Test func zoomEndsWhenFocusLeavesIt() {
        let ws = columns([1, 2])
        ws.layout = .bsp
        #expect(ws.zoomIn(toward: 1))
        #expect(ws.frameCamera(on: 2, area: area, gap: 0))
        #expect(ws.view == nil)
    }

    // MARK: Presets with titles

    @Test func titledTilesWin() {
        let preset = WorkspacePreset(layout: .bsp, tiles: [.init(apps: ["Ghostty"]), .init(apps: ["Ghostty"], title: "paw")])
        #expect(preset.slot(for: "Ghostty", title: "~/repos/paw") == 1)
        #expect(preset.slot(for: "Ghostty", title: "~") == 0)
        let ws = Workspace(name: "1", layout: .bsp)
        ws.arrange(preset, windows: [(id: 1, app: "Ghostty", title: "zsh"), (id: 2, app: "Ghostty", title: "paw")], area: area)
        #expect(ws.tiles.first { $0.slot == 1 }?.windows == [2])
        #expect(ws.tiles.first { $0.slot == 0 }?.windows == [1])
    }
}

struct OverviewLayoutTests {
    @Test func cardsFitAndStageKeepsTheAspect() {
        let b = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let l = OverviewLayout(bounds: b, top: 30, cardCount: 11, aspect: 16.0 / 10)
        #expect(l.cards.count == 11)
        #expect(l.cards.first!.minX >= 32 && l.cards.last!.maxX <= 1440 - 32 + 1)
        #expect(abs(l.stage.width / l.stage.height - 1.6) < 0.02)
        #expect(l.stage.minY > l.rail.maxY && l.stage.maxY < l.footer.minY)
        let rel = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let placed = OverviewLayout.place(rel, in: l.stage)
        let back = OverviewLayout.unplace(CGPoint(x: placed.minX, y: placed.minY), from: l.stage, to: CGRect(x: 100, y: 50, width: 1000, height: 625))
        #expect(abs(back.x - 600) < 1 && abs(back.y - 50) < 1)
    }

    @Test func neighboursAmongFloatingWindows() {
        let frames = [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.4, y: 0.2, width: 0.3, height: 0.3)]
        #expect(OverviewLayout.neighbor(of: frames[0], .east, among: [frames[1]]) == 0)
        #expect(OverviewLayout.neighbor(of: frames[1], .west, among: [frames[0]]) == 0)
    }
}

struct NewCommandTests {
    @Test func parses() throws {
        #expect(try Command.parse("undo") == .undo)
        #expect(try Command.parse("redo") == .redo)
        #expect(try Command.parse("focus back") == .focus(.back))
        #expect(try Command.parse("focus forward") == .focus(.forward))
        #expect(try Command.parse("find  Safari docs ") == .find("Safari docs"))
        #expect(try Command.parse("overview") == .overview)
        #expect(try Command.parse("zoom in") == .zoom(in: true))
        #expect(try Command.parse("move-workspace next") == .moveWorkspace(.next))
        #expect(try Command.parse("move-workspace 2") == .moveWorkspace(.index(2)))
        #expect(KeySpec.parse("hyper+š") == KeySpec.parse("hyper+["))
        #expect(KeySpec.parse("hyper+đ") == KeySpec.parse("hyper+]"))
        #expect(try Command.parse("zoom out") == .zoom(in: false))
        #expect(try Command.parse("layout columns") == .layout(.columns))
        #expect(try Command.parse("layout master") == .layout(.master))
        #expect(try Command.parse("layout canvas") == .layout(.bsp))
        #expect(throws: ConfigProblem.self) { try Command.parse("find ") }
    }

    @Test func mouseOverviewHudConfig() throws {
        let c = try ConfigLoader.decode(Data("""
        { mouse: { dropZones: false, gestures: [ { button: "back", direction: "up", command: "overview" } ] },
          overview: { thumbnails: "off" }, hud: { workspace: false } }
        """.utf8))
        #expect(!c.mouse.dropZones && c.mouse.seamHandles && c.mouse.gestures.count == 1 && c.mouse.gestures[0].buttonNumber == 3)
        #expect(c.overview.thumbnails == "off" && !c.hud.workspace)
        var bad = PawConfig()
        bad.mouse.gestures = [.init(button: "left", direction: "sideways", command: "nope")]
        #expect(ConfigLoader.warnings(bad).filter { $0.hasPrefix("mouse.gestures") }.count == 3)
        #expect(ConfigLoader.unknownKeys(Data("{ mouse: { drop: true }, hud: { x: 1 } }".utf8)) == ["hud.x", "mouse.drop"])
    }
}
