import SwiftUI
import Sparkle

// Sparkle verifies the feed and archive and owns installation. A probe never installs.
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    struct Commands { var probe: () -> Void; var install: () -> Void }
    private let commands: Commands?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
    private var started = false
    @Published private(set) var canCheck = false
    @Published private(set) var isChecking = false
    @Published private(set) var isUpdating = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var status = "点击检查获取最新版本"
    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String
        return version ?? "开发版本"
    }
    var buttonTitle: String {
        if isUpdating { return "更新中…" }
        if isChecking { return "检查中…" }
        return availableVersion == nil ? "检查更新" : "立即更新"
    }
    var actionEnabled: Bool { canCheck && !isChecking && !isUpdating }
    init(commands:Commands? = nil) {
        self.commands = commands
        super.init()
        if commands != nil { canCheck = true }
        else { controller.updater.publisher(for: \.canCheckForUpdates).assign(to:&$canCheck) }
    }
    func start() {
        guard commands == nil, !started else { return }
        guard Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") != nil else {
            status = "此版本尚未配置更新服务"; return
        }
        // Migrate the old automatic-install preference: updates now require the user's click.
        controller.updater.automaticallyDownloadsUpdates = false
        do { try controller.updater.start(); started = true }
        catch { status = "更新服务未能启动，请稍后重试" }
    }
    func performAction() {
        guard actionEnabled else { return }
        if availableVersion != nil {
            isUpdating = true; status = "请在更新窗口中确认安装"
            if let commands { commands.install() } else { controller.checkForUpdates(nil) }
        } else { check() }
    }
    func check() {
        guard actionEnabled else { return }
        if commands == nil && controller.updater.sessionInProgress {
            status = "已有更新任务，请查看更新窗口"; controller.checkForUpdates(nil); return
        }
        isChecking = true; status = "正在检查更新…"
        if let commands { commands.probe() } else { controller.updater.checkForUpdateInformation() }
    }
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }
    private func found(_ version:String) {
        availableVersion = version
        if !isUpdating { status = "发现新版本 "+version }
    }
    private func noUpdate() { availableVersion = nil; status = "已是最新版本" }
    private func finish(_ error:Error?) {
        let updating = isUpdating
        isChecking = false; isUpdating = false
        if let error {
            let value = error as NSError
            if value.domain == SUSparkleErrorDomain && value.code == 1001 { noUpdate() }
            else if value.domain == SUSparkleErrorDomain && value.code == 4007 {
                status = availableVersion.map { "发现新版本 "+$0 } ?? "更新已取消"
            } else { status = updating ? "更新未完成，请重试" : "检查失败，请稍后重试" }
        } else if let version = availableVersion { status = "发现新版本 "+version }
    }
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) { found(item.displayVersionString) }
    func updaterDidNotFindUpdate(_ updater:SPUUpdater) { noUpdate() }
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) { finish(error) }

    // Isolated fixtures inject commands so preview/self-tests never start an update session.
    static func fixture(version:String? = nil) -> AppUpdater {
        let model = AppUpdater(commands:Commands(probe:{},install:{}))
        if let version { model.found(version) }
        return model
    }
    static func probeDiagnostic() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = AppUpdater()
        model.start()
        guard model.started && model.canCheck else { throw namingError(model.status) }
        model.check()
        let deadline = Date().addingTimeInterval(25)
        while model.isChecking && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
        guard !model.isChecking else { throw namingError("更新检查超时") }
        print("UPDATE PROBE: \(model.versionText); \(model.status); newVersion=\(model.availableVersion ?? "none"); no installation requested")
        if model.status.hasPrefix("检查失败") { throw namingError(model.status) }
    }
    static func selfTest() throws {
        var probes = 0, installs = 0
        let model = AppUpdater(commands:Commands(probe:{ probes += 1 },install:{ installs += 1 }))
        for name in ["updater:didFindValidUpdate:","updaterDidNotFindUpdate:","updater:didFinishUpdateCycleForUpdateCheck:error:"] {
            try verify(model.responds(to:NSSelectorFromString(name)),"Sparkle delegate callback must be connected: "+name)
        }
        model.performAction(); model.performAction()
        try verify(probes == 1 && installs == 0 && model.isChecking,"Checking and repeat clicks must never start installation")
        model.found("9.9.9"); model.finish(nil)
        try verify(model.buttonTitle == "立即更新" && model.actionEnabled,"A discovered update must enable the install action after the probe ends")
        model.performAction(); model.performAction()
        try verify(installs == 1 && !model.actionEnabled,"Only an explicit click on the available update may start the installer, exactly once")
        model.finish(NSError(domain:SUSparkleErrorDomain,code:4007))
        try verify(model.buttonTitle == "立即更新" && model.actionEnabled,"Cancelled installation must remain retryable")
        model.noUpdate(); model.finish(NSError(domain:SUSparkleErrorDomain,code:1001))
        try verify(model.availableVersion == nil && model.buttonTitle == "检查更新" && model.status == "已是最新版本","A no-update result must clear any stale install offer")
        model.check(); model.finish(NSError(domain:NSURLErrorDomain,code:NSURLErrorNotConnectedToInternet))
        try verify(model.actionEnabled && !model.isChecking && installs == 1,"Network errors must allow a retry without starting installation")
        let comparator = SUStandardVersionComparator.default
        for (new,old) in [("20261031.1","14"),("20261031.2","20261031.1"),("20261101.1","20261031.99")] {
            try verify(comparator.compareVersion(new,toVersion:old) == .orderedDescending,"Dated builds must increase across same-day releases, dates and legacy versions")
        }
        print("PASS: updater delegate wiring, check-only probe, new-version install action, duplicate-click guard, cancel/retry, no-update and offline recovery")
    }
}

struct SettingsUpdateControls: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            VStack(alignment:.leading,spacing:4) {
                Text("当前版本").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                Text(updater.versionText).font(.system(size:12,weight:.medium)).textSelection(.enabled)
            }
            Button(updater.buttonTitle) { updater.performAction() }
                .buttonStyle(SoftWorkspaceButton(peach:updater.availableVersion != nil)).disabled(!updater.actionEnabled)
            Text(updater.status).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}

struct UpdateMenu: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Button(updater.buttonTitle) { updater.performAction() }.disabled(!updater.actionEnabled)
        Toggle("自动检查更新",isOn:Binding(get:{updater.automaticChecks},set:{updater.automaticChecks = $0}))
    }
}
