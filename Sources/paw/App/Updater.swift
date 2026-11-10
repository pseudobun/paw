import AppKit
import PawCore
import Sparkle

/// Sparkle updates from the appcast on GitHub (SUFeedURL in Info.plist). Only for a paw.app
/// that carries Sparkle and a public key, i.e. release builds; local builds skip it.
///
/// Checks you start (menu, `paw update`) first probe the feed without UI: Sparkle's own "up to
/// date" and error alerts are modal and would stall the main queue, and with it window
/// management and the CLI, until dismissed. Only a found update opens Sparkle's (non-modal) window.
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking
        case available(String)
        case upToDate
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "idle"
            case .checking: return "checking"
            case .available(let v): return "paw \(v) is available"
            case .upToDate: return "paw \(AppPaths.version) is the newest version"
            case .failed(let e): return "update check failed: \(e)"
            }
        }
    }

    private(set) var state = State.idle
    /// Runs once the probe started by `checkNow` has an answer.
    var onResult: ((State) -> Void)?

    private var controller: SPUStandardUpdaterController?
    /// The version the probe found; shown once its cycle has ended (Sparkle ignores a check
    /// started while another runs).
    private var found: String?

    var isAvailable: Bool { controller != nil }

    func start(_ config: PawConfig.Updates) {
        guard controller == nil, AppPaths.isAppBundle,
              let key = AppPaths.appBundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty
        else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        apply(config)
        do { try c.updater.start() } catch {
            Log.app.error("updater: \(error.localizedDescription, privacy: .public)")
            controller = nil
        }
    }

    func apply(_ config: PawConfig.Updates) {
        guard let u = controller?.updater else { return }
        u.automaticallyChecksForUpdates = config.check
        u.automaticallyDownloadsUpdates = config.check && config.automatic
        u.updateCheckInterval = 24 * 60 * 60
    }

    /// Menu and `paw update`: probe, then show Sparkle's window only for a new version.
    func checkNow() {
        guard let u = controller?.updater, state != .checking else { return }
        guard u.canCheckForUpdates else {
            // A check (or an update) is already under way; bring its window forward.
            NSApp.activate(ignoringOtherApps: true)
            controller?.checkForUpdates(nil)
            return
        }
        state = .checking
        found = nil
        u.checkForUpdateInformation()
    }

    private func finish(_ s: State) {
        guard state == .checking else { return }
        state = s
        Log.app.info("updates: \(s.text, privacy: .public)")
        onResult?(s)
        if case .available = s {
            showWindow(tries: 30)
        }
    }

    /// Sparkle's window for the found update, once the probe's session has let go (a check
    /// started before that is ignored).
    private func showWindow(tries: Int) {
        guard let controller else { return }
        guard controller.updater.canCheckForUpdates else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showWindow(tries: tries - 1) }
            } else {
                Log.app.error("updates: Sparkle stayed busy; no window")
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private func found(_ v: String) {
        guard state == .checking else { return }
        found = v
    }

    private func cycleEnded(_ error: String?) {
        guard state == .checking else { return }
        if let v = found { finish(.available(v)) } else { finish(.failed(error ?? "no answer")) }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let v = item.displayVersionString
        Task { @MainActor in self.found(v) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in self.finish(.upToDate) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let message = error.map { ($0 as NSError).localizedDescription }
        Task { @MainActor in self.cycleEnded(message) }
    }
}
