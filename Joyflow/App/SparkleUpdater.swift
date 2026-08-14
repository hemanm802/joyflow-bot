import Sparkle

/// Sparkle 2 wrapper. Starts only when `SUPublicEDKey` is present so a missing
/// key does not throw a "failed to start" alert on every launch.
@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    private var controller: SPUStandardUpdaterController?

    var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").isEmpty
    }

    func startIfNeeded() {
        guard isConfigured, controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        startIfNeeded()
        controller?.checkForUpdates(nil)
    }
}
