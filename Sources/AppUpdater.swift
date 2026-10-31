import SwiftUI
import Sparkle

// Sparkle owns scheduling, preferences, archive validation and atomic installation.
// This object is only started by the real app delegate, never by fixture/self-test modes.
@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    private let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
    @Published private(set) var canCheck = false
    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to:&$canCheck)
    }
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") != nil else { return }
        controller.startUpdater()
    }
    func check() { controller.checkForUpdates(nil) }
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticInstallation: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyDownloadsUpdates = newValue }
    }
}

struct UpdateMenu: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Button("检查更新…") { updater.check() }.disabled(!updater.canCheck)
        Toggle("自动检查更新",isOn:Binding(get:{updater.automaticChecks},set:{updater.automaticChecks = $0}))
        Toggle("自动下载并安装更新",isOn:Binding(get:{updater.automaticInstallation},set:{updater.automaticInstallation = $0}))
    }
}
