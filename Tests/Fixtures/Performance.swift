import AppKit
import Darwin

/// Local, static windows; stdout is a JSON-line protocol, never a latency estimate.
final class PerformanceFixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private let count: Int

    init(count: Int) { self.count = count }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for i in 1...count {
            let window = NSWindow(contentRect: NSRect(x: 80 + i * 8, y: 100 + i * 8, width: 400, height: 300),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = String(format: "PAW Perf %02d", i)
            window.minSize = NSSize(width: 80, height: 80)
            window.isReleasedWhenClosed = false
            let text = NSTextField(labelWithString: window.title)
            text.frame = NSRect(x: 20, y: 20, width: 200, height: 40)
            window.contentView?.addSubview(text)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global().async {
            while let command = readLine() {
                DispatchQueue.main.async {
                    switch command {
                    case "state": self.reply()
                    case "quit": NSApp.terminate(nil)
                    default: self.write(["error": "unknown fixture command"])
                    }
                }
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func reply() {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        let frames: [[String: Any]] = windows.map { window in
            let r = window.frame
            return ["id": window.windowNumber, "title": window.title,
                    "frame": ["x": r.minX, "y": primary - r.maxY, "w": r.width, "h": r.height],
                    "focused": foreground && window.isKeyWindow, "minimized": window.isMiniaturized]
        }
        let screens: [[String: Any]] = NSScreen.screens.map {
            ["x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height,
             "scale": $0.backingScaleFactor, "maxFPS": $0.maximumFramesPerSecond]
        }
        write(["schema": 1, "pid": getpid(), "windows": frames, "screens": screens,
               "appearance": NSApp.effectiveAppearance.name.rawValue])
    }

    private func write(_ value: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            fputs("cannot encode fixture state\n", stderr)
            NSApp.terminate(nil)
        }
    }
}

let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 8
guard (2...32).contains(count), count.isMultiple(of: 2) else {
    fputs("fixture needs an even window count from 2 to 32\n", stderr)
    exit(64)
}
let app = NSApplication.shared
let fixture = PerformanceFixture(count: count)
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()
