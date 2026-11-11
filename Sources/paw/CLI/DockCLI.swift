import Foundation

/// `paw dock install|uninstall|status`: the Dock helper that moves windows through the window
/// server (see DockBridge and Sources/PawDock). install/uninstall need root (sudo).
enum DockCLI {
    static let dir = "/Library/Application Support/paw"
    static var payload: String { dir + "/PawDock.dylib" }
    static var loader: String { dir + "/paw-dock-loader" }
    static var versionFile: String { dir + "/VERSION" }
    static let label = "com.pseudobun.paw.dock"
    static var plist: String { "/Library/LaunchDaemons/\(label).plist" }

    static func run(_ args: [String]) -> Int32 {
        switch args.first ?? "status" {
        case "install": return install()
        case "uninstall": return uninstall()
        case "status": return status()
        default:
            fputs("usage: paw dock install|uninstall|status\n", stderr)
            return 64
        }
    }

    static func status() -> Int32 {
        let sip = DockBridge.sipAllowsLoading
        let installed = FileManager.default.fileExists(atPath: plist)
        let loaded = FileManager.default.fileExists(atPath: DockBridge.socketPath) && DockBridge.shared.ping()
        print("sip: \(sip ? "debugging restrictions off (helper allowed)" : "on (helper not allowed; see README)")")
        print("installed: \(installed ? "yes" : "no (sudo paw dock install)")")
        print("loaded: \(loaded ? "yes" : "no")")
        let bundled = DockBridge.bundledVersion, installedVersion = DockBridge.installedVersion
        let running = loaded ? DockBridge.shared.loadedVersion : nil
        print("version: this paw \(bundled ?? "-"), installed \(installed ? installedVersion ?? "older" : "-"), in Dock \(running ?? "-")")
        if installed, let advice = DockBridge.advice(bundled: bundled, installed: installedVersion, loaded: running) {
            print("helper \(advice)")
            return 1
        }
        return loaded ? 0 : 1
    }

    static func install() -> Int32 {
        guard geteuid() == 0 else { fputs("paw: run it with sudo: sudo paw dock install\n", stderr); return 77 }
        guard DockBridge.sipAllowsLoading else {
            fputs("paw: SIP doesn't allow it; turn off its debugging restrictions first (README, \"Faster workspace switching\")\n", stderr)
            return 1
        }
        let src = AppPaths.appBundle.bundleURL.appending(path: "Contents/Resources/dock")
        let fm = FileManager.default
        var restarted = false
        let previous = DockBridge.installedVersion
        let version = DockBridge.readVersion(src.appending(path: "VERSION").path)
        guard fm.fileExists(atPath: src.appending(path: "PawDock.dylib").path) else {
            fputs("paw: this build has no Dock helper (\(src.path))\n", stderr)
            return 1
        }
        do {
            // Root's, writable by no one else: the loader refuses anything else (it ends up in Dock).
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0])
            // An existing one keeps its owner and mode: make them root's, and refuse a symlink.
            var st = stat()
            guard lstat(dir, &st) == 0, st.st_mode & S_IFMT == S_IFDIR else {
                fputs("paw: \(dir) is not a directory\n", stderr)
                return 1
            }
            try fm.setAttributes([.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: dir)
            try? fm.removeItem(atPath: versionFile)
            for (name, mode) in [("PawDock.dylib", 0o644), ("paw-dock-loader", 0o755), ("VERSION", 0o644)] {
                let to = dir + "/" + name
                let from = src.appending(path: name).path
                try? fm.removeItem(atPath: to)
                // A build without scripts/bundle.sh has no VERSION.
                if name == "VERSION", !fm.fileExists(atPath: from) { continue }
                try fm.copyItem(atPath: from, toPath: to)
                try fm.setAttributes([.posixPermissions: mode, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: to)
            }
            let daemon: [String: Any] = [
                "Label": label,
                "ProgramArguments": [loader, "--watch", payload],
                "RunAtLoad": true,
                "KeepAlive": true,
                "StandardErrorPath": "/var/log/paw-dock.log",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: daemon, format: .xml, options: 0)
            // Already set up the same way (reinstalling after an update): restart the daemon on
            // the new loader in place. Unloading and loading it again would register it with
            // background task management anew, which logs errors racing its own last update.
            if fm.contents(atPath: plist) == data, launchctl(["print", "system/\(label)"]) == 0,
               launchctl(["kickstart", "-k", "system/\(label)"]) == 0 {
                restarted = true
            } else {
                _ = launchctl(["bootout", "system/\(label)"])
                try data.write(to: URL(fileURLWithPath: plist))
                try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: plist)
            }
        } catch {
            fputs("paw: \(error.localizedDescription)\n", stderr)
            return 1
        }
        guard restarted || launchctl(["bootstrap", "system", plist]) == 0 else {
            fputs("paw: launchctl bootstrap failed\n", stderr)
            return 1
        }
        // Loading a new helper into a Dock that already runs one changes nothing (Dock has a
        // library by that path already): a restarted Dock gets the new one.
        if needsDockRestart(previous: previous, new: version) {
            restartDock()
            print("installed; restarted Dock so it loads the new helper, and it loads whenever Dock starts (log: /var/log/paw-dock.log)")
        } else {
            print("installed; the helper loads into Dock now and whenever Dock starts (log: /var/log/paw-dock.log)")
        }
        return 0
    }

    /// Dock may run another helper than the one just installed: none was installed, an older
    /// one, or one without a version (before versions, or a build without scripts/bundle.sh).
    static func needsDockRestart(previous: String?, new: String?) -> Bool {
        guard let previous, let new else { return true }
        return previous != new
    }

    /// launchd starts Dock again at once, and the daemon loads the helper into it.
    private static func restartDock() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    static func uninstall() -> Int32 {
        guard geteuid() == 0 else { fputs("paw: run it with sudo: sudo paw dock uninstall\n", stderr); return 77 }
        _ = launchctl(["bootout", "system/\(label)"])
        for p in [plist, payload, loader, versionFile] { try? FileManager.default.removeItem(atPath: p) }
        try? FileManager.default.removeItem(atPath: dir)
        // What's already in Dock stays until Dock restarts.
        print("uninstalled; restart Dock (killall Dock) to unload what's still running")
        return 0
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

// MARK: Updating the helper after paw updates

extension DockCLI {
    /// The helper is installed, may load, and isn't this paw's: paw was updated (Sparkle or
    /// Homebrew) and the helper changed with it.
    static var isOutdated: Bool {
        guard DockBridge.sipAllowsLoading, FileManager.default.fileExists(atPath: plist),
              let bundled = DockBridge.bundledVersion else { return false }
        return DockBridge.installedVersion != bundled
    }

    static let installCommand = "sudo paw dock install"

    /// Says once per helper version that the new helper needs installing. paw doesn't install it
    /// itself: that needs root, and macOS's administrator prompt for a script looks like malware.
    static func noteUpdateOnce(defaults: UserDefaults = .standard, bundled: String? = DockBridge.bundledVersion,
                               isOutdated: () -> Bool = { DockCLI.isOutdated }, show: () -> Void) {
        let key = "dockHelperNotedVersion"
        guard let bundled, defaults.string(forKey: key) != bundled, isOutdated() else { return }
        defaults.set(bundled, forKey: key)
        show()
    }
}
