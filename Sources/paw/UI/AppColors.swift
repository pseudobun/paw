import AppKit
import PawCore

/// Each app's own colour (BrandColor over its app icon), cached by app name.
final class AppColors {
    static let shared = AppColors()
    private var cache: [String: ARGB?] = [:]
    private var images: [String: CGImage?] = [:]

    /// The app's own icon, for apps sketchybar-app-font has no glyph for.
    func image(for app: String, side: Int) -> CGImage? {
        // A few sizes only: callers draw it into any rect, and every pixel size (a zooming
        // overview, a dragged placeholder) would otherwise be another image kept for good.
        let side = Self.bucket(side)
        let key = "\(app)@\(side)"
        if let i = images[key] { return i }
        if images.count >= Self.maxImages { images.removeAll(keepingCapacity: true) }
        var i: CGImage?
        if !app.isEmpty, let url = Self.appURL(app) {
            var rect = CGRect(x: 0, y: 0, width: side, height: side)
            i = NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        images[key] = i
        return i
    }

    static let maxImages = 256

    /// The smallest of 16, 32, … 1024 pixels at least `side` (1024 at most).
    static func bucket(_ side: Int) -> Int {
        var b = 16
        while b < min(max(side, 1), 1024) { b *= 2 }
        return b
    }

    /// The colour for an app's icon: the config's override, else the picked one; nil when off or
    /// the icon has no clear colour.
    func color(for app: String, icons: PawConfig.Icons) -> ARGB? {
        if let c = icons.colors[app] { return c }
        guard icons.brandColors, !app.isEmpty else { return nil }
        if let c = cache[app] { return c }
        let c = pick(app)
        cache[app] = c
        return c
    }

    private func pick(_ app: String) -> ARGB? {
        guard let url = Self.appURL(app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let side = 48
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        ctx.draw(cg, in: rect)
        guard let data = ctx.data else { return nil }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
        return BrandColor.pick(rgba: bytes)
    }

    static func appURL(_ app: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == app }), let url = running.bundleURL {
            return url
        }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let url = URL(fileURLWithPath: dir).appending(path: app + ".app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
