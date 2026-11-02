// Isolated installer regression; never runs in a normal application launch.
import AppKit
import Sparkle
@MainActor final class UpdateFixtureDriver:NSObject,SPUUserDriver {
 var root:URL!
 var window:NSWindow!
 func show(_ message:String) {
  let line = message+"\n"
  let url = root.appendingPathComponent("events.log")
  let old = (try? String(contentsOf:url,encoding:.utf8)) ?? ""
  try? (old+line).write(to:url,atomically:true,encoding:.utf8)
  print(message);fflush(stdout)
 }
 func show(_ request:SPUUpdatePermissionRequest,reply:@escaping(SUUpdatePermissionResponse)->Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks:false,sendSystemProfile:false)) }
 func showUserInitiatedUpdateCheck(cancellation:@escaping()->Void) {}
 func showUpdateFound(with appcastItem:SUAppcastItem,state:SPUUserUpdateState,reply:@escaping(SPUUserUpdateChoice)->Void) { show("FOUND");reply(.install) }
 func showUpdateReleaseNotes(with downloadData:SPUDownloadData) {}
 func showUpdateReleaseNotesFailedToDownloadWithError(_ error:Error) {}
 func showUpdateNotFoundWithError(_ error:Error,acknowledgement:@escaping()->Void) { show("NOT FOUND \(error)");acknowledgement() }
 func showUpdaterError(_ error:Error,acknowledgement:@escaping()->Void) { show("ERROR \(error)");acknowledgement();exit(1) }
 func showDownloadInitiated(cancellation:@escaping()->Void) {show("DOWNLOAD")}
 func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength:UInt64) {}
 func showDownloadDidReceiveData(ofLength length:UInt64) {}
 func showDownloadDidStartExtractingUpdate() {show("EXTRACT")}
 func showExtractionReceivedProgress(_ progress:Double) {}
 func showReady(toInstallAndRelaunch reply:@escaping(SPUUserUpdateChoice)->Void) {guard window.attachedSheet == nil else { show("FAIL: modal sheet still blocks installation");exit(1) };show("INSTALL: production settings sheet released");reply(.install)}
 func showInstallingUpdate(withApplicationTerminated applicationTerminated:Bool,retryTerminatingApplication:@escaping()->Void) {show("TERMINATING \(applicationTerminated)")}
 func showUpdateInstalledAndRelaunched(_ relaunched:Bool,acknowledgement:@escaping()->Void) {show("INSTALLED");acknowledgement()}
 func dismissUpdateInstallation() {}
}

import SwiftUI

@MainActor final class UpdateFixturePresentation:ObservableObject { @Published var shown = true }
@MainActor struct UpdateFixtureSettingsHost:View {
 @ObservedObject var presentation:UpdateFixturePresentation
 let store:Store
 let updater:AppUpdater
 let closed:()->Void
 var body:some View {
  Color.clear.frame(width:1060,height:700).sheet(isPresented:$presentation.shown) {
   WorkspaceSettingsView(store:store,updater:updater,close:{ presentation.shown = false;closed() },openPending:{})
  }
 }
}
@MainActor final class UpdateFixtureApplicationDelegate:NSObject,NSApplicationDelegate {
 let root:URL
 init(root:URL) { self.root = root }
 func applicationWillTerminate(_ notification:Notification) {
  try? Data("terminated normally\n".utf8).write(to:root.appendingPathComponent("terminated"))
 }
}
@MainActor func updateInstallationFixture() throws {
 let app = Bundle.main
 guard let identifier = app.bundleIdentifier,identifier.hasPrefix("local.guiyu.updatefixture."),
       let path = app.object(forInfoDictionaryKey:"GuiyuUpdateFixtureRoot") as? String else { throw namingError("仅允许独立临时更新测试副本") }
 let root = URL(fileURLWithPath:path).standardizedFileURL
 let configuration = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("fixture.json"))) as! [String:String]
 guard configuration["identifier"] == identifier,app.bundleURL.standardizedFileURL.path == configuration["host"] else { throw namingError("更新测试路径不匹配") }
 NSApplication.shared.setActivationPolicy(.prohibited)
 let delegate = UpdateFixtureApplicationDelegate(root:root);NSApp.delegate = delegate
 let driver = UpdateFixtureDriver();driver.root = root
 var sparkle:SPUUpdater!
 let model = AppUpdater(commands:AppUpdater.Commands(probe:{sparkle.checkForUpdateInformation()},install:{sparkle.checkForUpdates()}))
 sparkle = SPUUpdater(hostBundle:app,applicationBundle:app,userDriver:driver,delegate:model)
 try sparkle.start()
 model.performAction()
 try namingRegionWait({!model.isChecking},"Signed fixture feed checking completes",seconds:25)
 try verify(model.availableVersion != nil,"A real newer update is discovered")
 let store = Store(stateURL:root.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
 let presentation = UpdateFixturePresentation()
 let host = NSHostingView(rootView:UpdateFixtureSettingsHost(presentation:presentation,store:store,updater:model,closed:{driver.show("SETTINGS CLOSED")}))
 let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:1060,height:700),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 window.contentView = host;window.alphaValue = 0;window.ignoresMouseEvents = true;driver.window = window
 window.orderBack(nil)
 try namingRegionWait({window.attachedSheet != nil},"Actual production SwiftUI settings sheet is attached",seconds:8)
 driver.show("SETTINGS ATTACHED")
 model.performAction()
 try namingRegionWait({window.attachedSheet == nil},"Explicit install action dismisses the actual production settings sheet",seconds:8)
 driver.show("SETTINGS RELEASED BEFORE QUIT")
 DispatchQueue.main.asyncAfter(deadline:.now()+60) {driver.show("FAIL: fixture installation timed out");exit(1)}
 withExtendedLifetime((driver,model,sparkle,window,delegate,presentation,store)) { NSApp.run() }
}
