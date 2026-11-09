import AppKit
import PawCore
import QuartzCore

/// `paw preview out.png`: draws paw's labels and islands with the current config onto a mock
/// window next to a mock sketchybar, so the look can be checked without a display session.
enum Preview {
    static func run(_ args: [String]) -> Int32 {
        guard let out = args.first(where: { !$0.hasPrefix("--") }) else {
            fputs("paw preview <out.png> [--fonts=DIR] [--scale=2]\n", stderr)
            return 64
        }
        if let dir = args.first(where: { $0.hasPrefix("--fonts=") })?.dropFirst(8) {
            registerFonts(in: String(dir).expandingTilde)
        }
        let scale = args.first { $0.hasPrefix("--scale=") }.flatMap { Double($0.dropFirst(8)) } ?? 2
        let settings = Settings(url: Settings.defaultURL)
        let style = Style(settings.config.appearance)
        if style.appFont == nil { fputs("note: \(settings.config.appearance.appFont) is not installed; islands show no app icon\n", stderr) }
        if style.labelFont.familyName != settings.config.appearance.font {
            fputs("note: \(settings.config.appearance.font) is not installed; using \(style.labelFont.familyName ?? "?")\n", stderr)
        }
        let scene = Scene(style: style, config: settings.config, icons: settings.icons, scale: scale)
        let root = scene.build()
        guard let png = render(root, scale: scale) else { fputs("render failed\n", stderr); return 1 }
        do { try png.write(to: URL(fileURLWithPath: out.expandingTilde)) } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
        print(out)
        return 0
    }

    static func registerFonts(in dir: String) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
        for u in urls where ["ttf", "otf"].contains(u.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }

    static func render(_ root: CALayer, scale: CGFloat) -> Data? {
        let w = Int(root.bounds.width * scale), h = Int(root.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        displayAll(root)
        root.render(in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func displayAll(_ l: CALayer) {
        l.displayIfNeeded()
        l.sublayers?.forEach(displayAll)
    }
}

/// Mock desktop: sketchybar on top, a window with controls, and paw's three modes.
private struct Scene {
    let style: Style
    let config: PawConfig
    let icons: AppIconMap
    let scale: CGFloat
    let width: CGFloat = 1180
    let height: CGFloat = 900

    var c: PawConfig.Colors { style.colors }

    /// Places `l` with its top-left at (x, y) in a top-left coordinate space.
    func place(_ l: CALayer, in parent: CALayer, x: CGFloat, y: CGFloat) {
        let h = parent.bounds.height
        l.frame = CGRect(x: x, y: h - y - l.bounds.height, width: l.bounds.width, height: l.bounds.height)
        parent.addSublayer(l)
    }

    func box(_ w: CGFloat, _ h: CGFloat, fill: ARGB, radius: CGFloat = 6, border: ARGB? = nil) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.backgroundColor = fill.cg
        l.cornerRadius = radius
        l.cornerCurve = .continuous
        if let border { l.borderColor = border.cg; l.borderWidth = 1 }
        return l
    }

    func text(_ s: String, _ color: ARGB, size: CGFloat = 12, w: CGFloat? = nil) -> TextLayer {
        let t = TextLayer()
        t.contentsScale = scale
        t.text = NSAttributedString(string: s, attributes: [.font: Style.font(config.appearance.font, size: size, weight: "medium"),
                                                             .foregroundColor: color.ns])
        t.bounds = CGRect(x: 0, y: 0, width: w ?? t.text.size().width + 2, height: t.text.size().height + 4)
        return t
    }

    func build() -> CALayer {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        root.backgroundColor = ARGB(0xff0e_0e0b).cg
        root.contentsScale = scale

        // sketchybar: front_app island on the left, clock island on the right.
        var front: [Island.Segment] = []
        if let g = style.appGlyph(icons.glyph(for: "Safari")) { front.append(.init(text: g, gapAfter: 5)) }
        front.append(.init(text: style.text("Safari", c.fg, font: style.islandBold)))
        place(Island.make(front, style: style, scale: scale), in: root, x: 12, y: 6)
        place(Island.make([.init(text: style.text("09 Nov  13:42", c.fg, font: style.islandBold))], style: style, scale: scale),
              in: root, x: width - 140, y: 6)

        let panels: [(String, CGFloat)] = [("hint", 60), ("search", 340), ("scroll", 620)]
        for (mode, top) in panels { drawPanel(mode, root: root, top: top) }
        return root
    }

    func drawPanel(_ mode: String, root: CALayer, top: CGFloat) {
        let win = box(width - 80, 260, fill: ARGB(0xff23_231d), radius: 10, border: c.border)
        place(win, in: root, x: 40, y: top)
        // Traffic lights, toolbar, sidebar, content.
        for (i, col) in [0xffff_5f57, 0xfffe_bc2e, 0xff28_c840].enumerated() {
            place(box(12, 12, fill: ARGB(UInt32(col)), radius: 6), in: win, x: 14 + CGFloat(i) * 20, y: 14)
        }
        let toolbar: [(String, CGFloat)] = [("◀", 90), ("▶", 122), ("⟳", 154)]
        for (t, x) in toolbar {
            let b = box(26, 22, fill: ARGB(0xff2f_2f27), radius: 6)
            place(b, in: win, x: x, y: 9)
            place(text(t, c.muted), in: b, x: 7, y: 2)
        }
        let field = box(380, 24, fill: ARGB(0xff18_1813), radius: 7, border: c.border)
        place(field, in: win, x: 300, y: 8)
        place(text("pseudobun.dev", c.muted), in: field, x: 10, y: 3)
        let sidebar = ["Favourites", "Recents", "Shared", "Downloads", "Projects"]
        for (i, s) in sidebar.enumerated() { place(text(s, c.fg), in: win, x: 22, y: 60 + CGFloat(i) * 34) }
        let links = ["Read the docs", "Open an issue", "Release notes", "Sign in", "Pricing", "Changelog"]
        for (i, s) in links.enumerated() {
            place(text(s, c.wave), in: win, x: 220 + CGFloat(i % 3) * 180, y: 70 + CGFloat(i / 3) * 60)
        }
        let check = box(14, 14, fill: ARGB(0xff18_1813), radius: 4, border: c.muted)
        place(check, in: win, x: 220, y: 200)
        place(text("Remember me", c.fg), in: win, x: 242, y: 197)
        let button = box(90, 26, fill: c.wave, radius: 7)
        place(button, in: win, x: 760, y: 194)
        place(text("Continue", ARGB(0xff10_1010)), in: button, x: 16, y: 4)

        let targets: [CGRect] = [
            CGRect(x: 90, y: 9, width: 26, height: 22), CGRect(x: 122, y: 9, width: 26, height: 22), CGRect(x: 154, y: 9, width: 26, height: 22),
            CGRect(x: 300, y: 8, width: 380, height: 24),
        ] + sidebar.indices.map { CGRect(x: 22, y: 60 + CGFloat($0) * 34, width: 120, height: 18) }
          + links.indices.map { CGRect(x: 220 + CGFloat($0 % 3) * 180, y: 70 + CGFloat($0 / 3) * 60, width: 110, height: 18) }
          + [CGRect(x: 220, y: 200, width: 120, height: 16), CGRect(x: 760, y: 194, width: 90, height: 26)]

        let codes = LabelGenerator.labels(count: targets.count, charset: config.hint.charset)
        let glyph = icons.glyph(for: "Safari")
        let islandY = config.appearance.islandTop + top - 60

        switch mode {
        case "hint":
            // State after typing the first key of a two-key label.
            let typed = codes.first { $0.count > 1 }.map { String($0.prefix(1)) } ?? ""
            for (i, f) in targets.enumerated() {
                let l = LabelLayer.make(code: codes[i], style: style, scale: scale)
                let match = codes[i].hasPrefix(typed)
                l.update(style: style, typed: match ? typed.count : 0)
                l.opacity = match ? 1 : max(0.12, Float(config.appearance.unmatchedOpacity))
                place(l, in: win, x: f.minX, y: f.minY)
            }
            let n = codes.filter { $0.hasPrefix(typed) }.count
            place(modeIsland(glyph, "hint", "\(n)/\(codes.count)"), in: root, x: 0, y: islandY, centered: true)
        case "search":
            let picked = [10, 13]
            for (rank, i) in picked.enumerated() {
                let f = targets[i]
                let l = LabelLayer.make(code: codes[rank], style: style, scale: scale)
                if rank == 0 {
                    style.decorate(l, radius: config.appearance.labelRadius, fill: c.islandHi, border: c.accent)
                    let ring = box(f.width + 4, f.height + 4, fill: ARGB(0), radius: 5, border: c.accent)
                    ring.borderWidth = 1.5
                    place(ring, in: win, x: f.minX - 2, y: f.minY - 2)
                }
                place(l, in: win, x: f.minX, y: f.minY)
            }
            var segs: [Island.Segment] = []
            if let g = style.appGlyph(glyph) { segs.append(.init(text: g, gapAfter: 8)) }
            segs.append(.init(text: style.text("rel", c.fg, font: style.islandBold), gapAfter: 1))
            segs.append(.init(text: style.text("▏", c.accent)))
            let island = Island.make(segs, style: style, scale: scale, width: config.search.width,
                                     trailing: style.text("1/2  link", c.muted))
            place(island, in: root, x: 0, y: islandY, centered: true)
        default:
            let areas = [CGRect(x: 10, y: 44, width: 180, height: 206), CGRect(x: 200, y: 44, width: win.bounds.width - 210, height: 206)]
            for (i, a) in areas.enumerated() {
                let selected = i == 1
                if selected {
                    let ring = box(a.width - 4, a.height - 4, fill: ARGB(0), radius: 8, border: c.accent.withAlpha(0.8))
                    ring.borderWidth = 1.5
                    place(ring, in: win, x: a.minX + 2, y: a.minY + 2)
                }
                let badge = LabelLayer()
                badge.contentsScale = scale
                badge.centered = true
                badge.text = style.text("\(i + 1)", selected ? c.accent : c.wave, font: style.labelFont)
                let h = config.appearance.labelHeight
                badge.bounds = CGRect(x: 0, y: 0, width: max(h, badge.text.size().width + config.appearance.labelPaddingX * 2), height: h)
                style.decorate(badge, radius: config.appearance.labelRadius, fill: selected ? c.islandHi : c.island,
                               border: selected ? c.accent : c.border)
                place(badge, in: win, x: a.minX + 8, y: a.minY + 8)
            }
            place(modeIsland(glyph, "scroll", "2/2  hjkl"), in: root, x: 0, y: islandY, centered: true)
        }
    }

    func modeIsland(_ glyph: String, _ mode: String, _ note: String) -> CALayer {
        var segs: [Island.Segment] = []
        if let g = style.appGlyph(glyph) { segs.append(.init(text: g, gapAfter: 6)) }
        segs.append(.init(text: style.text("Safari", c.fg, font: style.islandBold), gapAfter: 10))
        segs.append(.init(text: style.text(mode, c.muted), gapAfter: 8))
        segs.append(.init(text: style.text(note, c.dim)))
        return Island.make(segs, style: style, scale: scale)
    }

    func place(_ l: CALayer, in parent: CALayer, x: CGFloat, y: CGFloat, centered: Bool) {
        place(l, in: parent, x: centered ? ((parent.bounds.width - l.bounds.width) / 2).rounded() : x, y: y)
    }
}
