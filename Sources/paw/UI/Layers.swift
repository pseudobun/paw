import AppKit
import PawCore
import QuartzCore

/// Draws an attributed string, vertically centred, `insetX` from the left (or centred).
class TextLayer: CALayer {
    var text = NSAttributedString() { didSet { setNeedsDisplay() } }
    var insetX: CGFloat = 0
    var centered = false

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let l = layer as? TextLayer {
            text = l.text
            insetX = l.insetX
            centered = l.centered
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(in ctx: CGContext) {
        if centered { drawCentered(in: ctx); return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let size = text.size()
        let x = centered ? (bounds.width - size.width) / 2 : insetX
        // Centre the font's line box; round to whole points so glyphs stay crisp.
        let y = ((bounds.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Centres the ink (glyph outlines), not the advance box: app-font icons have uneven side
    /// bearings, so centring the line box leaves them off to one side.
    private func drawCentered(in ctx: CGContext) {
        // An app's own icon (no app font) is an attachment, which Core Text doesn't draw.
        if text.length > 0, let image = (text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.image,
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let s = image.size
            ctx.draw(cg, in: CGRect(x: ((bounds.width - s.width) / 2).rounded(), y: ((bounds.height - s.height) / 2).rounded(),
                                    width: s.width, height: s.height))
            return
        }
        let line = CTLineCreateWithAttributedString(text)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let px = 1 / max(contentsScale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v / px).rounded() * px }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: snap((bounds.width - ink.width) / 2 - ink.minX),
                                   y: snap((bounds.height - ink.height) / 2 - ink.minY))
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// A sketchybar island: segments of text side by side on a rounded fill.
enum Island {
    struct Segment {
        var text: NSAttributedString
        var gapAfter: CGFloat = 5
    }

    /// Edge padding like sketchybar's island helper: edge (5) + item padding (5).
    static let edge: CGFloat = 10

    static func make(_ segments: [Segment], style: Style, scale: CGFloat, width: CGFloat? = nil,
                     trailing: NSAttributedString? = nil, fill: ARGB? = nil, border: ARGB? = nil) -> CALayer {
        let h = style.islandHeight
        let root = CALayer()
        root.contentsScale = scale
        var x = edge
        for (i, s) in segments.enumerated() {
            let t = TextLayer()
            t.contentsScale = scale
            t.text = s.text
            let w = s.text.size().width.rounded(.up)
            t.frame = CGRect(x: x, y: 0, width: w + 1, height: h)
            root.addSublayer(t)
            x += w + (i == segments.count - 1 ? 0 : s.gapAfter)
        }
        var total = x + edge
        if let trailing {
            let tw = trailing.size().width.rounded(.up)
            let t = TextLayer()
            t.contentsScale = scale
            t.text = trailing
            let w = max(width ?? 0, total + 10 + tw)
            t.frame = CGRect(x: w - edge - tw, y: 0, width: tw + 1, height: h)
            root.addSublayer(t)
            total = w
        }
        root.bounds = CGRect(x: 0, y: 0, width: max(width ?? 0, total), height: h)
        style.decorate(root, radius: style.a.radius, fill: fill, border: border)
        return root
    }
}
