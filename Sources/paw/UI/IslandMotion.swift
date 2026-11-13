import AppKit
import QuartzCore

/// How an island panel moves to the island it shows next, in the tip bar's motion: the island
/// glides to its new size and place (220 ms, easeOutQuint) while its content slides and
/// cross-fades into the new one. Works on glass (the panel's frame animates and the glass follows)
/// and without (the island's own layer glides inside a panel grown to cover both places).
final class IslandMotion {
    enum Transition: Equatable {
        /// Swap at once.
        case none
        /// From the island shown now. `direction` +1 (next) brings the new content in from the
        /// right, -1 (previous) from the left, 0 only cross-fades.
        case glide(direction: Int)
        /// The island comes up: its content slides in from `direction`'s side (on glass with
        /// direction 0, it rises into place like `Glass.settle`).
        case enter(direction: Int)
    }

    static let glide: CFTimeInterval = 0.22
    static let fadeOut: CFTimeInterval = 0.1
    static let fadeIn: CFTimeInterval = 0.16
    static let ease = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    /// How far content slides, in points.
    var shift: CGFloat = 12

    /// The island shown now: its chrome and its rows, kept apart so the chrome can glide while
    /// the rows swap.
    private var chrome: CALayer?
    private var rows: CALayer?
    /// Where the panel is headed (it may still be gliding there).
    private var target: CGRect?
    private var generation = 0
    /// Steps the panel's frame through a glass glide.
    private var ticker: Timer?

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shows the island `l` in `panel` at `frame` (Cocoa coordinates).
    func show(_ l: CALayer, at frame: CGRect, in panel: NSPanel, host: GlassHost, _ transition: Transition = .none) {
        guard let root = host.content.layer else { return }
        generation += 1
        let gen = generation
        // The rows move into their own layer; `l` keeps only the island's chrome.
        let content = CALayer()
        content.contentsScale = l.contentsScale
        for row in l.sublayers ?? [] { content.addSublayer(row) }
        let from = panel.isVisible ? (target ?? panel.frame) : frame
        target = frame
        let oldRows = rows
        let glass = Glass.tint(of: l) != nil

        var direction = 0
        var glide = false
        switch transition {
        case .glide(let d) where panel.isVisible && chrome != nil && !Self.reduceMotion:
            // Only a nearby move glides (not one to another display).
            glide = abs(from.midX - frame.midX) < 400 && abs(from.midY - frame.midY) < 400
            direction = d
        default: break
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chrome = l
        rows = content
        for layer in [l, content] { layer.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull()] }

        guard glide else {
            // Stop a glide still under way, or it would carry on to its old place.
            ticker?.invalidate()
            ticker = nil
            panel.setFrame(frame, display: false)
            fit(host)
            l.frame = CGRect(origin: .zero, size: frame.size)
            content.frame = l.frame
            root.sublayers = [l, content]
            host.adopt(l)
            if case .enter(let d) = transition, !Self.reduceMotion {
                if d != 0 {
                    slide(content, from: CGFloat(d) * shift, fadeIn: true)
                } else if glass {
                    Glass.settle(content)
                }
            }
            CATransaction.commit()
            panel.orderFrontRegardless()
            return
        }

        // Glass: the panel's frame is stepped to the new one; the glass fills it, and the rows are
        // put back in its middle on every step (the glass doesn't resize its content in between).
        let start = panel.frame
        func place(_ size: CGSize) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fit(host)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            l.frame = CGRect(origin: .zero, size: size)
            content.position = mid
            oldRows?.position = mid
            CATransaction.commit()
        }
        if glass {
            content.bounds = CGRect(origin: .zero, size: frame.size)
            root.sublayers = [l, oldRows, content].compactMap { $0 }
            host.adopt(l)
            place(start.size)
        } else {
            // Grow the panel to cover both places; the island's own layer glides between them.
            let union = from.union(frame)
            let f = from.offsetBy(dx: -union.minX, dy: -union.minY)
            let t = frame.offsetBy(dx: -union.minX, dy: -union.minY)
            panel.setFrame(union, display: false)
            oldRows?.frame = f
            l.frame = t
            content.frame = t
            root.sublayers = [l, oldRows, content].compactMap { $0 }
            host.adopt(l)
            if f != t {
                l.add(Self.anim("bounds", NSValue(rect: CGRect(origin: .zero, size: f.size))), forKey: "glide.bounds")
                l.add(Self.anim("position", NSValue(point: CGPoint(x: f.midX, y: f.midY))), forKey: "glide.position")
                if l.shadowPath != nil {
                    let r = l.cornerRadius
                    let path = CGPath(roundedRect: CGRect(origin: .zero, size: f.size), cornerWidth: min(r, f.width / 2),
                                      cornerHeight: min(r, f.height / 2), transform: nil)
                    l.add(Self.anim("shadowPath", path), forKey: "glide.shadow")
                }
            }
        }

        // The new rows come in from the way it went, the old ones leave the other way.
        slide(content, from: CGFloat(direction) * shift, fadeIn: true)
        if let oldRows {
            oldRows.removeAllAnimations()
            oldRows.opacity = 0
            let out = CABasicAnimation(keyPath: "transform.translation.x")
            out.fromValue = 0
            out.toValue = -CGFloat(direction) * shift
            out.duration = Self.glide
            out.timingFunction = Self.ease
            oldRows.add(out, forKey: "slide")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Self.fadeOut
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            oldRows.add(fade, forKey: "fade")
        }

        let settle = { [weak self, weak panel] in
            guard let self, let panel, gen == generation else { return }
            ticker?.invalidate()
            ticker = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(frame, display: false)
            fit(host)
            l.frame = CGRect(origin: .zero, size: frame.size)
            content.frame = l.frame
            root.sublayers = [l, content]
            CATransaction.commit()
        }
        CATransaction.setCompletionBlock(glass ? nil : settle)
        CATransaction.commit()
        panel.orderFrontRegardless()
        ticker?.invalidate()
        ticker = nil
        guard glass else { return }
        let began = CACurrentMediaTime()
        let scale = panel.backingScaleFactor
        func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let t = Timer(timeInterval: 1 / 120, repeats: true) { [weak self, weak panel] t in
            guard let self, let panel, gen == generation else { t.invalidate(); return }
            let p = min(1, (CACurrentMediaTime() - began) / Self.glide)
            guard p < 1 else { settle(); return }
            let e = CGFloat(Self.easeOutQuint(p))
            let r = CGRect(x: px(start.minX + (frame.minX - start.minX) * e),
                           y: px(start.minY + (frame.minY - start.minY) * e),
                           width: px(start.width + (frame.width - start.width) * e),
                           height: px(start.height + (frame.height - start.height) * e))
            panel.setFrame(r, display: false)
            place(r.size)
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// The tip bar's curve, cubic-bezier(0.22, 1, 0.36, 1), at `t` (0…1).
    static func easeOutQuint(_ t: Double) -> Double {
        // Solve x(s) = t for the curve's parameter s (Newton), then take y(s).
        func bez(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s
        }
        var s = t
        for _ in 0..<8 {
            let x = bez(s, 0.22, 0.36) - t
            let dx = 3 * 0.22 * (1 - s) * (1 - s) + 6 * (0.36 - 0.22) * s * (1 - s) + 3 * (1 - 0.36) * s * s
            guard abs(dx) > 1e-6 else { break }
            s = min(1, max(0, s - x / dx))
        }
        return bez(s, 1, 1)
    }

    /// Makes the island's view fill the panel now, glass or not.
    private func fit(_ host: GlassHost) {
        if let parent = host.content.superview, host.content.frame != parent.bounds {
            host.content.frame = parent.bounds
        }
    }

    private func slide(_ l: CALayer, from dx: CGFloat, fadeIn: Bool) {
        if dx != 0 {
            let a = CABasicAnimation(keyPath: "transform.translation.x")
            a.fromValue = dx
            a.toValue = 0
            a.duration = Self.glide
            a.timingFunction = Self.ease
            l.add(a, forKey: "slide")
        }
        if fadeIn {
            let f = CABasicAnimation(keyPath: "opacity")
            f.fromValue = 0
            f.toValue = 1
            f.duration = Self.fadeIn
            f.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.add(f, forKey: "fade")
        }
    }

    private static func anim(_ key: String, _ from: Any?) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.duration = glide
        a.timingFunction = ease
        return a
    }
}
