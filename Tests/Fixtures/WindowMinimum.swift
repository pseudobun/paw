import AppKit

// A real AX client: it initially refuses a half-screen tile, then accepts it.
final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func window(_ title: String, minimum: CGFloat) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 500),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.minSize = NSSize(width: minimum, height: 250)
        w.isReleasedWhenClosed = false
        w.contentView = NSTextField(labelWithString: title)
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = window("PAW minimum regression", minimum: 1000)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = self.window("PAW minimum companion", minimum: 200)
        }
        DispatchQueue.global().async {
            while let command = readLine() {
                DispatchQueue.main.async {
                    switch command {
                    case "lower-minimum":
                        main.minSize = NSSize(width: 400, height: 250)
                        // No resize/title notification: focusing the placeholder must retry its size.
                        print("minimum-lowered")
                    case "focused":
                        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                        print(frontmost && main.isKeyWindow ? "focused" : "not-focused")
                    case "parked":
                        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(main.windowNumber)) as? [[String: Any]]
                        if let bounds = info?.first?[kCGWindowBounds as String] as? [String: Any],
                           let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
                            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                            let parked = NSScreen.screens.allSatisfy {
                                let screen = CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY,
                                                    width: $0.frame.width, height: $0.frame.height)
                                let intersection = frame.intersection(screen)
                                return intersection.isNull || intersection.width <= 1 && intersection.height <= 1
                            }
                            print(parked ? "parked" : "not-parked")
                        } else {
                            print("bounds-unavailable")
                        }
                    default: return
                    }
                    fflush(stdout)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let fixture = Fixture()
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()
