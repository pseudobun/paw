import AppKit
import PawCore

/// Moves windows to new frames over `durationMs` along a curve, at 60 fps. In "start" mode a
/// window gets its final size first and only its position animates (apps redraw once instead
/// of every frame). A new layout mid-animation continues from where windows are.
final class Animator {
    private struct Move {
        let window: Window
        var from: CGRect
        var to: CGRect
    }

    private var moves: [WindowID: Move] = [:]
    private var start: CFTimeInterval = 0
    private var timer: Timer?
    private var measurement: Performance.Interval?
    var settings: () -> PawConfig.Animation = { .init() }
    /// Called when a run finishes (indicators redraw then).
    var onFinish: (() -> Void)?

    var isRunning: Bool { timer != nil }

    func animate(_ targets: [(Window, CGRect)]) {
        let s = settings()
        let changed = targets.filter { $0.0.frame.integral != $0.1.integral || moves[$0.0.id] != nil }
        guard s.enabled, s.durationMs > 0, changed.count <= max(1, s.maxWindows), !changed.isEmpty else {
            Performance.count("animation_direct_targets", by: targets.count)
            for (w, r) in targets {
                moves[w.id] = nil
                if w.frame.integral != r.integral { w.setFrame(r) }
            }
            if moves.isEmpty { stop() }
            onFinish?()
            return
        }
        let now = CACurrentMediaTime()
        Performance.count("animated_targets", by: changed.count)
        // Continue moves still running from their current point.
        let progress = curvePosition(now)
        for (w, r) in changed {
            var from = w.frame
            if let m = moves[w.id] { from = Easing.lerp(m.from, m.to, progress) }
            if s.resize == "start", from.size != r.size {
                // Its final size now (through its app's queue), the position animates from here.
                // `frame` keeps the old size, so the last frame sends size, position, size again:
                // an app clamps a size that doesn't fit at its old position to the screen.
                from.size = r.size
                AXQueue.run { AXQueue.enqueue(w, size: r.size, origin: w.frame.origin, settle: false) }
            }
            moves[w.id] = Move(window: w, from: from, to: r)
        }
        start = now
        if timer == nil {
            measurement = Performance.begin("animation")
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }

    private func curvePosition(_ now: CFTimeInterval) -> Double {
        let s = settings()
        let t = s.durationMs > 0 ? (now - start) * 1000 / s.durationMs : 1
        return s.curve.value(t)
    }

    /// Every frame's moves go to the apps' queues (or the Dock helper, as one update): a frame
    /// never waits for an app, and a slow one only skips the frames it can't keep up with.
    private func tick() {
        AXQueue.run { step() }
    }

    private func step() {
        Performance.count("animation_ticks")
        let s = settings()
        let now = CACurrentMediaTime()
        let t = s.durationMs > 0 ? (now - start) * 1000 / s.durationMs : 1
        if t >= 1 {
            for m in moves.values { m.window.setFrame(m.to) }
            moves = [:]
            stop()
            onFinish?()
            return
        }
        let p = s.curve.value(t)
        for m in moves.values {
            let r = Easing.lerp(m.from, m.to, p)
            if s.resize == "animate" {
                m.window.setFrame(r, settle: false)
            } else {
                m.window.setPosition(r.origin)
            }
        }
    }

    func cancel(_ id: WindowID) { moves[id] = nil }

    func stop() {
        timer?.invalidate()
        timer = nil
        Performance.end(measurement)
        measurement = nil
    }
}
