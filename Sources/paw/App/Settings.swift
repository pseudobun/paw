import Foundation
import PawCore

/// Loads `~/.config/paw/config.json5`, writes the template on first launch and reloads on save.
/// A broken file keeps the last good config.
final class Settings {
    private(set) var config = PawConfig()
    private(set) var error: String?
    private(set) var warnings: [String] = []
    private(set) var icons: AppIconMap = .bundled
    var onChange: (() -> Void)?
    let url: URL
    private var watcher: FileWatcher?

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
    }

    func load(notify: Bool = true) {
        let raw = (try? Data(contentsOf: url)) ?? Data()
        do {
            config = try ConfigLoader.decode(raw)
            error = nil
            warnings = ConfigLoader.unknownKeys(raw).map { "unknown key \($0)" } + ConfigLoader.warnings(config)
        } catch {
            self.error = "\(error)"
            Log.app.error("config: \(self.error ?? "", privacy: .public)")
        }
        loadIcons()
        if notify { onChange?() }
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
