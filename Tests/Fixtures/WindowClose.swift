import AppKit

final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [String: NSWindow] = [:]
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
                    case "focus":
                        self.windows[name]?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        print("ok")
                    case "close":
                        self.windows[name]?.close()
                        print("ok")
                    case "hover":
                        CGWarpMouseCursorPosition(CGPoint(x: Double(parts[1])!, y: Double(parts[2])!))
                        CGAssociateMouseAndMouseCursorPosition(1)
                        print("ok")
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
