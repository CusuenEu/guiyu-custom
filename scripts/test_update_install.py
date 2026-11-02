#!/usr/bin/env python3
"""Maintainer-only signed installer regression on a unique temporary app.

Requires ./build.sh and the existing tiduse1988.guiyu Sparkle signing key.
No installed app, user preference domain or user file is replaced.
Retains the temporary root and logs for inspection.
"""
from pathlib import Path
import subprocess,tempfile,plistlib,json,uuid,threading,http.server,time,shutil,sys,os
repo=Path(__file__).resolve().parents[1]
root=Path(tempfile.mkdtemp(prefix='GuiyuUpdaterInstallCheck-'));print('Fixture root: '+str(root),flush=True)
identifier='local.guiyu.updatefixture.'+uuid.uuid4().hex
(root/'state').mkdir();(root/'web').mkdir();(root/'new').mkdir();(root/'Applications').mkdir()
host=root/'Applications/归屿.app';new=root/'new/归屿.app'
subprocess.run(['ditto',str(repo/'dist/归屿.app'),str(host)],check=True)
class Quiet(http.server.SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(root/'web'),**kw)
 def log_message(self,*a):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Quiet);threading.Thread(target=server.serve_forever,daemon=True).start();base='http://127.0.0.1:'+str(server.server_port)+'/'
p=host/'Contents/Info.plist';info=plistlib.loads(p.read_bytes());info.pop('NSServices',None);info.update(CFBundleIdentifier=identifier,CFBundleVersion='1.0',CFBundleShortVersionString='1.0',GuiyuUpdateFixtureRoot=str(root),SUFeedURL=base+'appcast.xml',SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,LSUIElement=True,NSAppTransportSecurity={'NSAllowsLocalNetworking':True});p.write_bytes(plistlib.dumps(info));subprocess.run(['codesign','--force','--deep','--sign','-',str(host)],check=True,capture_output=True)
(new/'Contents/MacOS').mkdir(parents=True);stub=root/'new.swift';stub.write_text('''import AppKit
final class Relaunch:NSObject,NSApplicationDelegate {
 func applicationDidFinishLaunching(_ notification:Notification) {
  let path = Bundle.main.object(forInfoDictionaryKey:"GuiyuUpdateFixtureRoot") as! String
  let result = "version="+(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as! String)+"\\npath="+Bundle.main.bundlePath
  try! result.write(toFile:path+"/relaunched",atomically:true,encoding:.utf8)
  NSApp.terminate(nil)
 }
}
let app = NSApplication.shared;app.setActivationPolicy(.prohibited)
let delegate = Relaunch();app.delegate = delegate;app.run()
''');subprocess.run(['swiftc',str(stub),'-o',str(new/'Contents/MacOS/Guiyu')],check=True)
newinfo=dict(info);newinfo.update(CFBundleVersion='2.0',CFBundleShortVersionString='2.0');(new/'Contents/Info.plist').write_bytes(plistlib.dumps(newinfo));subprocess.run(['codesign','--force','--deep','--sign','-',str(new)],check=True,capture_output=True)
archive=root/'web/update.zip';subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(new),str(archive)],check=True)
tools=repo/'.build/artifacts/sparkle/Sparkle/bin';subprocess.run([str(tools/'generate_appcast'),'--account','tiduse1988.guiyu','--download-url-prefix',base,'--maximum-deltas','0',str(root/'web')],check=True);subprocess.run([str(tools/'sign_update'),'--account','tiduse1988.guiyu','--verify',str(root/'web/appcast.xml')],check=True)
(root/'fixture.json').write_text(json.dumps({'identifier':identifier,'host':str(host)}))
with (root/'host.log').open('w') as log:
 process=subprocess.Popen([str(host/'Contents/MacOS/Guiyu'),'--update-install-fixture'],stdout=log,stderr=subprocess.STDOUT)
 try: code=process.wait(timeout=90)
 except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=10);raise
for _ in range(100):
 if (root/'relaunched').exists():break
 time.sleep(.1)
print((root/'host.log').read_text()[-5000:],flush=True)
for name in ['events.log','terminated','relaunched']:
 print(name+': '+((root/name).read_text() if (root/name).exists() else 'MISSING'),flush=True)
assert code==0,'Old host did not terminate successfully'
assert (root/'terminated').exists(),'Normal AppKit termination callback missing'
assert (root/'relaunched').exists() and 'version=2.0' in (root/'relaunched').read_text(),'Installed app did not relaunch'
installed=plistlib.loads((host/'Contents/Info.plist').read_bytes());assert installed['CFBundleVersion']=='2.0';subprocess.run(['codesign','--verify','--deep','--strict',str(host)],check=True)
assert (host/'Contents/MacOS/Guiyu').read_bytes()==(new/'Contents/MacOS/Guiyu').read_bytes()
print('PASS: signed update downloaded, production settings sheet dismissed, normal quit, physical bundle replacement and new-version relaunch; only a uniquely identified temporary application was updated',flush=True)
server.shutdown();subprocess.run(['defaults','delete',identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
