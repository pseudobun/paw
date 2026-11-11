import AppKit

// Run unbundled through paw's exec command so the test uses paw's Accessibility grant.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--move-pointer",
   let x = Double(CommandLine.arguments[2]), let y = Double(CommandLine.arguments[3]) {
    guard AXIsProcessTrusted() else { exit(1) }
    let point = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
            mouseButton: .left)?.post(tap: .cghidEventTap)
    exit(0)
}

final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [String: NSWindow] = [:]
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        CommandLine.arguments.contains("--quit-on-close")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().async {
            while let line = readLine() {
                DispatchQueue.main.async {
                    let parts = line.split(separator: " ").map(String.init)
                    guard let command = parts.first else { return }
                    let name = parts.count > 1 ? parts[1] : ""
                    switch command {
                    case "new":
                        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
                                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                        window.title = "PAW-close-" + name
                        window.minSize = NSSize(width: name == "placeholder" ? 10000 : 100, height: 100)
                        window.isReleasedWhenClosed = false
                        self.windows[name] = window
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        print(window.windowNumber)
                    case "close":
                        if parts.count == 4 {
                            CGWarpMouseCursorPosition(CGPoint(x: Double(parts[2])!, y: Double(parts[3])!))
                            CGAssociateMouseAndMouseCursorPosition(1)
                        }
                        self.windows[name]?.close()
                        print("ok")
                    case "quit":
                        if parts.count == 3 {
                            CGWarpMouseCursorPosition(CGPoint(x: Double(parts[1])!, y: Double(parts[2])!))
                            CGAssociateMouseAndMouseCursorPosition(1)
                        }
                        print("ok")
                        fflush(stdout)
                        NSApp.terminate(nil)
                    case "front":
                        print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
                    case "pointer":
                        let p = NSEvent.mouseLocation
                        print("\(p.x) \((NSScreen.screens.first?.frame.height ?? 0) - p.y)")
                    case "frame":
                        if let f = self.windows[name]?.frame {
                            print("\(f.minX) \((NSScreen.screens.first?.frame.height ?? 0) - f.maxY) \(f.width) \(f.height)")
                        } else { print("missing") }
                    case "focused":
                        print(NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                              ? self.windows.first(where: { $0.value.isKeyWindow })?.key ?? "none" : "background")
                    default: print("unknown")
                    }
                    fflush(stdout)
                }
            }
        }
    }
}
let app = NSApplication.shared
let fixture = Fixture()
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()
