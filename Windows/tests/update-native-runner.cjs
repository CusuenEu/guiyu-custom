"use strict";
const { app }=require('electron'), fs=require('node:fs/promises'), path=require('node:path'), crypto=require('node:crypto');
const temp=process.env.GUIYU_UPDATE_NATIVE;
if(process.env.CI!=='true'||!temp)throw Error('Disposable CI only');
app.setPath('temp',temp);
for(const event of ['before-quit','will-quit','quit'])app.on(event,()=>console.log(`UPDATE old app ${event}, pid=${process.pid}`));
app.whenReady().then(async()=>{
  const installer=process.env.GUIYU_UPDATE_INSTALLER, metadata=await fs.stat(installer), hash=crypto.createHash('sha256');
  for await(const chunk of require('node:fs').createReadStream(installer))hash.update(chunk);
  const digest='sha256:'+hash.digest('hex');
  const version=require(path.join(process.resourcesPath,'production.asar/version.json'));
  const url=`https://github.com/tiduse1988/guiyu/releases/download/windows-${version.date}-${String(version.sequence).padStart(2,'0')}/${version.assetPrefix}-Windows-${process.arch}-setup.exe`;
  const source=process.env.GUIYU_UPDATE_TEST_SOURCE==='1'?'app.asar':'production.asar';
  const {createInstallerUpdater}=require(path.join(process.resourcesPath,source,'src/install-update.cjs'));
  // Inject only the transport. The production download, integrity, helper,
  // shutdown, installation and restart paths execute unchanged.
  let phase;
  const install=createInstallerUpdater({app,fetch:async()=>new Response(require('node:fs').createReadStream(installer)),progress:p=>{if(p.phase!==phase){phase=p.phase;console.log('UPDATE phase: '+phase);}}});
  await install({url,kind:'installer',digest,size:metadata.size,packageVersion:version.packageVersion});
  console.log('UPDATE helper handoff complete, waiting for graceful quit');
}).catch(e=>{console.error(e);app.exit(1);});
