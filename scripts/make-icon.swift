// Renders Resources/icon/paw.svg on hop's dark gradient tile into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs iconutil; run from the repo root)
import AppKit

let svg = URL(fileURLWithPath: "Resources/icon/paw.svg")
guard let art = NSImage(contentsOf: svg) else { fatalError("cannot read \(svg.path)") }

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824 pt tile centred in 1024, continuous corners
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // hop's fill: #2A2A2E → #0D0D0F, top to bottom
    NSGradient(starting: NSColor(srgbRed: 0.16471, green: 0.16471, blue: 0.18039, alpha: 1),
               ending: NSColor(srgbRed: 0.05098, green: 0.05098, blue: 0.05882, alpha: 1))!
        .draw(in: path, angle: -90)
    let side = 680 * s
    art.draw(in: NSRect(x: (CGFloat(px) - side) / 2, y: (CGFloat(px) - side) / 2 - 10 * s, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "paw.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try render(1024).write(to: set.deletingLastPathComponent().appending(path: "paw-icon-preview.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
