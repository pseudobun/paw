import AppKit

// One binary: `paw <command>` is the CLI, plain `paw` (or paw.app) is the app.
CLI.runIfRequested(CommandLine.arguments)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) { app.run() }
