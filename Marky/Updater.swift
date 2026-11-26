import Combine
import Foundation
import Sparkle

/// In-app updates through Sparkle: Marky ▸ Check for Updates…, plus the periodic check Sparkle
/// offers on the second launch. The feed and the EdDSA public key are in Info.plist (project.yml);
/// an update that isn't signed with the matching private key is refused.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// False while a check is already running.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!
    private var observation: AnyCancellable?

    /// User default that points the updater at another feed, for testing a release before it is
    /// published. Updates from it must still carry a valid signature.
    nonisolated static let feedOverrideKey = "MarkyUpdateFeedURL"

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        let override = UserDefaults.standard.string(forKey: Self.feedOverrideKey)
        return override?.isEmpty == false ? override : nil
    }
}
