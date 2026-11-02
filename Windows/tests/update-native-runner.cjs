"use strict";
const { app }=require('electron'), fs=require('node:fs/promises'), path=require('node:path'), crypto=require('node:crypto');
const temp=process.env.GUIYU_UPDATE_NATIVE;
if(process.env.CI!=='true'||!temp)throw Error('Disposable CI only');
app.setPath('temp',temp);
app.whenReady().then(async()=>{
  const installer=process.env.GUIYU_UPDATE_INSTALLER, metadata=await fs.stat(installer), hash=crypto.createHash('sha256');
  for await(const chunk of require('node:fs').createReadStream(installer))hash.update(chunk);
  const digest='sha256:'+hash.digest('hex');
  const version=require(path.join(process.resourcesPath,'production.asar/version.json'));
  const url=`https://github.com/tiduse1988/guiyu/releases/download/windows-${version.date}-${String(version.sequence).padStart(2,'0')}/${version.assetPrefix}-Windows-${process.arch}-setup.exe`;
  const {createInstallerUpdater}=require(path.join(process.resourcesPath,'production.asar/src/install-update.cjs'));
  // Inject only the transport. The production download, integrity, helper,
  // shutdown, installation and restart paths execute unchanged.
  const install=createInstallerUpdater({app,fetch:async()=>new Response(require('node:fs').createReadStream(installer))});
  await install({url,kind:'installer',digest,size:metadata.size,packageVersion:version.packageVersion});
}).catch(e=>{console.error(e);app.exit(1);});
