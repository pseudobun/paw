import AppKit
import PawCore
import Sparkle

/// Sparkle updates from the appcast on GitHub (SUFeedURL in Info.plist). Only for a paw.app
/// that carries Sparkle and a public key, i.e. release builds; local builds skip it.
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    func start(_ config: PawConfig.Updates) {
        guard controller == nil, AppPaths.isAppBundle,
              let key = AppPaths.appBundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty
        else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
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

    /// "Check for Updates…": shows Sparkle's window, also when paw is up to date.
    func checkNow() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
}
