import Foundation
import PawCore

/// Loads `~/.config/paw/config.json5`, writes the template on first launch and reloads on save.
/// A broken file keeps the last good config.
final class Settings {
    private(set) var config = PawConfig()
    private(set) var error: String?
    private(set) var warnings: [String] = []
    private(set) var icons: AppIconMap = .bundled
    /// After a load that changed something. `configChanged`: the config (or the icon map) is
    /// new and needs applying; false when only the error or warnings changed (a broken save
    /// keeps the last good config, which is already in effect).
    var onChange: ((_ configChanged: Bool) -> Void)?
    let url: URL
    private var watcher: FileWatcher?
    /// `icons.map` lives in its own file (sketchybar's icon_map.lua): edits there reload too.
    private var iconWatcher: FileWatcher?

    /// `$PAW_CONFIG` overrides the location.
    static var defaultURL: URL {
        if let o = ProcessInfo.processInfo.environment["PAW_CONFIG"], !o.isEmpty {
            return URL(fileURLWithPath: o.expandingTilde)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/paw/config.json5")
    }

    init(url: URL = Settings.defaultURL) {
        self.url = url
        load(notify: false)
    }

    func start() {
        if !FileManager.default.fileExists(atPath: url.path) { writeTemplate() }
        load(notify: false)
        watcher?.stop()
        watcher = FileWatcher(url: url) { [weak self] in self?.load() }
        watchIcons()
    }

    /// Reads the file again. Nothing is announced when nothing changed: editors touch the folder
    /// (swap files, backups) and every save comes back through the watcher too. `force` (the
    /// menu's Reload, `paw reload`) applies the config even when it is the same.
    func load(notify: Bool = true, force: Bool = false) {
        let before = (config: config, error: error, warnings: warnings, icons: icons)
        let raw = (try? Data(contentsOf: url)) ?? Data()
        do {
            config = try ConfigLoader.decode(raw)
            error = nil
            warnings = ConfigLoader.unknownKeys(raw).map { "unknown key \($0)" } + ConfigLoader.warnings(config)
            config = config.clamped()
        } catch {
            self.error = "\(error)"
            // They were about the last good file; the broken one has only its error.
            warnings = []
            Log.app.error("config: \(self.error ?? "", privacy: .public)")
        }
        loadIcons()
        if watcher != nil { watchIcons() }
        let configChanged = config != before.config || icons != before.icons || force && error == nil
        guard notify, configChanged || force || error != before.error || warnings != before.warnings else { return }
        onChange?(configChanged)
    }

    /// Changes the config and writes the file (the watcher loads it). Not while it's broken.
    func save(_ change: (inout PawConfig) -> Void) {
        guard error == nil else { return }
        var c = config
        change(&c)
        guard c != config else { return }
        do {
            try ConfigTemplate.render(c).write(to: url, atomically: true, encoding: .utf8)
            load()
        } catch {
            Log.app.error("config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Watches the file `icons.map` names (again when the setting changes).
    private func watchIcons() {
        let path = config.icons.map.expandingTilde
        guard iconWatcher?.url.path != path else { return }
        iconWatcher?.stop()
        iconWatcher = path.isEmpty ? nil : FileWatcher(url: URL(fileURLWithPath: path)) { [weak self] in self?.load() }
    }

    private func loadIcons() {
        let path = config.icons.map.expandingTilde
        var map = AppIconMap.bundled
        if !path.isEmpty, let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let parsed = AppIconMap.parse(lua: text)
            if !parsed.exact.isEmpty { map = parsed }
        }
        icons = map.merging(config.icons.overrides)
    }

    private func writeTemplate() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ConfigTemplate.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.app.error("config template: \(error.localizedDescription, privacy: .public)")
        }
    }
}
