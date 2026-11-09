import AppKit
import PawCore
import QuartzCore

/// `paw preview out.png`: draws two tiled stacks with paw's indicators (one focused,
/// one hovered) under a mock sketchybar, using the current config.
enum Preview {
    static func run(_ args: [String]) -> Int32 {
        guard let out = args.first(where: { !$0.hasPrefix("--") }) else {
            fputs("paw preview <out.png> [--fonts=DIR] [--scale=2]\n", stderr)
            return 64
        }
        if let dir = args.first(where: { $0.hasPrefix("--fonts=") })?.dropFirst(8) { registerFonts(in: String(dir).expandingTilde) }
        let scale = args.first { $0.hasPrefix("--scale=") }.flatMap { Double($0.dropFirst(8)) } ?? 2
        let settings = Settings(url: Settings.defaultURL)
        let style = Style(settings.config.appearance)
        if style.appFont == nil { fputs("note: \(settings.config.appearance.appFont) is not installed; cells show initials\n", stderr) }
        let root = scene(style: style, config: settings.config, icons: settings.icons, scale: scale)
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

    static func scene(style: Style, config: PawConfig, icons: AppIconMap, scale: CGFloat) -> CALayer {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 820)
        let root = CALayer()
        root.bounds = screen
        root.contentsScale = scale
        root.backgroundColor = ARGB(0xff0e_0e0b).cg
        let c = style.colors

        func place(_ l: CALayer, _ r: CGRect) {
            l.frame = CGRect(x: r.minX, y: screen.height - r.maxY, width: r.width, height: r.height)
            root.addSublayer(l)
        }

        // sketchybar: front app island left, clock island right.
        let front = Island.make([.init(text: style.appGlyph(icons.glyph(for: "Discord"), app: "Discord", color: c.accent), gapAfter: 5),
                                 .init(text: style.text("Discord", c.fg, font: style.bold))], style: style, scale: scale)
        place(front, CGRect(origin: CGPoint(x: 12, y: 6), size: front.bounds.size))
        let clock = Island.make([.init(text: style.text("09 Nov  15:12", c.fg, font: style.bold))], style: style, scale: scale)
        place(clock, CGRect(origin: CGPoint(x: screen.width - 12 - clock.bounds.width, y: 6), size: clock.bounds.size))

        // Two tiled windows with the default padding, each the top of a stack.
        let left = CGRect(x: 44, y: 46, width: 660, height: 760)
        let right = CGRect(x: 716, y: 46, width: 680, height: 760)
        for (f, name) in [(left, "Discord"), (right, "Safari")] {
            let w = CALayer()
            w.backgroundColor = ARGB(0xff23_231d).cg
            w.cornerRadius = 10
            w.borderColor = c.border.cg
            w.borderWidth = 1
            place(w, f)
            for (i, col) in [0xffff_5f57, 0xfffe_bc2e, 0xff28_c840].enumerated() {
                let dot = CALayer()
                dot.backgroundColor = ARGB(UInt32(col)).cg
                dot.cornerRadius = 6
                place(dot, CGRect(x: f.minX + 14 + CGFloat(i) * 20, y: f.minY + 14, width: 12, height: 12))
            }
            let t = TextLayer()
            t.contentsScale = scale
            t.text = style.text(name, c.muted)
            place(t, CGRect(x: f.minX + 90, y: f.minY + 8, width: 200, height: 24))
        }

        let stacks = [
            Stack(space: 1, frame: left, items: [
                .init(id: 1, app: "Discord", title: "#general", isActive: true, hasFocus: true),
                .init(id: 2, app: "Spotify", title: "Spotify Premium", isActive: false, hasFocus: false),
                .init(id: 3, app: "Ghostty", title: "~/repos/paw", isActive: false, hasFocus: false),
            ]),
            Stack(space: 1, frame: right, items: [
                .init(id: 4, app: "Safari", title: "Apple", isActive: true, hasFocus: false),
                .init(id: 5, app: "Zed", title: "paw — StackController.swift", isActive: false, hasFocus: false),
                .init(id: 6, app: "Obsidian", title: "Repos", isActive: false, hasFocus: false),
                .init(id: 7, app: "Mail", title: "Inbox", isActive: false, hasFocus: false),
            ]),
        ]
        let m = config.indicator.metrics
        for (n, stack) in stacks.enumerated() {
            let (r, side) = IndicatorLayout.frame(window: stack.frame, screen: screen, count: stack.items.count,
                                                  side: config.indicator.side, metrics: m)
            let hovered = n == 1 ? 2 : nil
            let l = StackRenderer.layer(stack, size: r.size, style: style, config: config, icons: icons, scale: scale, hovered: hovered)
            l.opacity = stack.hasFocus ? 1 : Float(config.indicator.unfocusedOpacity)
            place(l, r)
            if let hovered {
                let t = StackRenderer.titleLayer(stack.items[hovered], style: style, icons: icons, scale: scale)
                let cell = IndicatorLayout.cell(hovered, metrics: m)
                let toRight = side == .left || side == .insideLeft
                let x = toRight ? r.maxX + 6 : r.minX - 6 - t.bounds.width
                place(t, CGRect(x: x, y: r.minY + cell.midY - t.bounds.height / 2, width: t.bounds.width, height: t.bounds.height))
            }
        }
        return root
    }
}
