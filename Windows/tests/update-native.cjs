"use strict";
// An actual old process downloads, exits, runs NSIS and restarts the replacement.
// Only disposable CI installation copies are touched; no user machine is used.
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const { spawn, execFileSync } = require("node:child_process");
async function run() {
  if (process.platform !== "win32" || process.env.CI !== "true") throw Error("Disposable Windows CI only");
  const { createPackage } = await import("@electron/asar");
  const version = require("../version.json"), out = path.resolve(__dirname, "../out");
  for (const arch of ["ia32", "x64"]) {
    const temp = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), `guiyu-auto-update-${arch}-`)));
    const runtime = path.join(temp, "旧程序 中文 & space"), shim = path.join(temp, "shim");
    let old, restartedPid, helperPid;
    try {
      await fs.cp(path.join(out, `Guiyu-win32-${arch}`), runtime, { recursive: true });
      const expected = crypto.createHash("sha256").update(await fs.readFile(path.join(runtime, "resources/app.asar"))).digest("hex");
      await fs.rename(path.join(runtime, "resources/app.asar"), path.join(runtime, "resources/production.asar"));
      await fs.rename(path.join(runtime, "resources/app.asar.unpacked"), path.join(runtime, "resources/production.asar.unpacked"));
      await fs.mkdir(shim);
      await fs.writeFile(path.join(shim, "package.json"), JSON.stringify({ name:`guiyu-update-native-${arch}`, version:"1.0.0", main:"runner.cjs" }));
      await fs.copyFile(path.join(__dirname, "update-native-runner.cjs"), path.join(shim, "runner.cjs"));
      await createPackage(shim, path.join(runtime, "resources/app.asar"));
      const sentinel = path.join(temp, "user-settings.json"); await fs.writeFile(sentinel, '{"preserve":"配置保留"}');
      old = spawn(path.join(runtime, "Guiyu.exe"), [], { env:{ ...process.env, GUIYU_REVIEW:"1", GUIYU_UPDATE_NATIVE:temp,
        GUIYU_UPDATE_INSTALLER:path.join(out, `${version.assetPrefix}-Windows-${arch}-setup.exe`), GUIYU_UPDATE_VERSION:version.packageVersion },
        stdio:["ignore","pipe","pipe"],windowsHide:true });
      old.stdout.on("data", d=>process.stdout.write(d)); old.stderr.on("data", d=>process.stderr.write(d));
      let exitCode; old.once("exit", c=>{exitCode=c;}); old.once("error",e=>{throw e;});
      const deadline = Date.now()+150000;
      let status;
      while (Date.now()<deadline) {
        for(const name of (await fs.readdir(temp)).filter(n=>n.startsWith("Guiyu-update-"))) {
          const dir=path.join(temp,name);
          try { helperPid=JSON.parse((await fs.readFile(path.join(dir,'ready.json'),'utf8')).replace(/^\uFEFF/,'')).pid; } catch {}
          try { status=JSON.parse((await fs.readFile(path.join(dir,'status.json'),'utf8')).replace(/^\uFEFF/,'')); } catch {}
        }
        if(status?.phase==='failed')throw Error(status.message);
        if(status?.phase==='completed') { restartedPid=status.processId; break; }
        await new Promise(r=>setTimeout(r,200));
      }
      if(!restartedPid)throw Error(`Update timed out: ${JSON.stringify(status)}`);
      if(exitCode!==0)throw Error(`Old app did not exit cleanly: ${exitCode}`);
      process.kill(restartedPid,0);
      const actual=crypto.createHash('sha256').update(await fs.readFile(path.join(runtime,'resources/app.asar'))).digest('hex');
      if(actual!==expected)throw Error('Installed application differs from the new release');
      if(await fs.readFile(sentinel,'utf8')!=='{"preserve":"配置保留"}')throw Error('User settings changed');
      console.log(`PASS ${arch}: verified streaming download, graceful process exit, real silent NSIS installation, exact new application and automatic restart; settings unchanged`);
    } finally {
      for(const pid of [restartedPid,old?.pid,helperPid].filter(Boolean))try{execFileSync('taskkill',['/PID',String(pid),'/T','/F'],{stdio:'ignore'});}catch{}
      const uninstall=path.join(runtime,'卸载归屿.exe');
      try { await fs.access(uninstall); execFileSync('powershell.exe',['-NoProfile','-Command',`$p=Start-Process -FilePath '${uninstall.replace(/'/g,"''")}' -ArgumentList '/S' -PassThru -Wait;if($p.ExitCode -ne 0){exit 1}`],{stdio:'inherit'}); } catch {}
      await fs.rm(temp,{recursive:true,force:true,maxRetries:15,retryDelay:300});
    }
  }
}
run().catch(e=>{console.error(e);process.exitCode=1;});
