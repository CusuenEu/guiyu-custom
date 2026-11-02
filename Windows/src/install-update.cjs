"use strict";
const fs = require("node:fs/promises"), path = require("node:path"), crypto = require("node:crypto");
const { spawn } = require("node:child_process");

function createInstallerUpdater({ fetch, app, progress = () => {}, launch = launchHelper, platform = process.platform }) {
  let installing = false;
  return async function install(update) {
    if (installing) throw Error("更新正在进行，请稍候。");
    if (platform !== "win32" || !app.isPackaged) throw Error("自动安装仅适用于已打包的 Windows 程序。");
    if (update.kind !== "installer" || !/^sha256:[a-f0-9]{64}$/i.test(update.digest || "") ||
        !Number.isSafeInteger(update.size) || update.size <= 0 || update.size > 600 * 1024 * 1024 ||
        !/^https:\/\/github\.com\/tiduse1988\/guiyu\/releases\/download\/[^/]+\/Guiyu-\d{8}-\d{2}-(?:test-)?Windows-(?:ia32|x64)-setup\.exe$/.test(update.url))
      throw Error("更新包来源或校验信息无效，请重新检查更新。");
    installing = true;
    let temp;
    try {
      const executable = app.getPath("exe"), installDir = path.dirname(executable);
      const probe = path.join(installDir, `.guiyu-update-${crypto.randomUUID()}`);
      try { const handle = await fs.open(probe, "wx"); await handle.close(); await fs.unlink(probe); }
      catch { throw Error("当前安装位置不可写，请把归屿安装到当前用户的可写目录后更新。"); }
      temp = await fs.mkdtemp(path.join(app.getPath("temp"), "Guiyu-update-"));
      const installer = path.join(temp, "update-setup.exe");
      const response = await fetch(update.url, { signal: AbortSignal.timeout(10 * 60 * 1000) });
      if (!response.ok || !response.body) throw Error(`更新包下载失败（${response.status}），请重试。`);
      const file = await fs.open(installer, "wx"), hash = crypto.createHash("sha256");
      let size = 0, notified = 0;
      progress({ phase: "downloading", percent: 0 });
      try {
        for await (const raw of response.body) {
          const chunk = Buffer.from(raw); size += chunk.length;
          if (size > update.size) throw Error("更新包大小异常，已停止安装。");
          hash.update(chunk);
          // FileHandle.write may write fewer bytes than requested.
          for (let offset = 0; offset < chunk.length;) {
            const { bytesWritten } = await file.write(chunk, offset, chunk.length - offset);
            if (!bytesWritten) throw Error("更新包无法写入磁盘。");
            offset += bytesWritten;
          }
          if (Date.now() - notified > 200) { progress({ phase: "downloading", percent: Math.floor(size / update.size * 100) }); notified = Date.now(); }
        }
      } finally { await file.close(); }
      progress({ phase: "verifying" });
      if (size !== update.size || hash.digest("hex") !== update.digest.slice(7).toLowerCase())
        throw Error("更新包校验失败，已删除下载文件，请重新检查更新。");
      const manifest = { installer, digest: update.digest.slice(7).toLowerCase(), installDir,
        executable, parentPid: process.pid, packageVersion: update.packageVersion,
        statusFile: path.join(temp, "status.json"), readyFile: path.join(temp, "ready.json") };
      const manifestFile = path.join(temp, "manifest.json"), helper = path.join(temp, "install.ps1");
      await fs.writeFile(manifestFile, JSON.stringify(manifest), "utf8");
      await fs.writeFile(helper, "\uFEFF" + await fs.readFile(path.join(__dirname, "../scripts/update-install.ps1"), "utf8"), "utf8");
      await launch(helper, manifestFile, manifest.readyFile);
      progress({ phase: "installing" });
      // Let the IPC result reach the settings window before graceful shutdown.
      setTimeout(() => app.quit(), 300);
      return { automatic: true, message: "下载校验完成，正在退出安装；完成后会自动打开归屿。" };
    } catch (error) {
      if (temp) await fs.rm(temp, { recursive: true, force: true }).catch(() => {});
      installing = false;
      throw error;
    }
  };
}
async function launchHelper(helper, manifest, readyFile) {
  const child = spawn("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper, "-Manifest", manifest],
    { detached: true, windowsHide: true, stdio: "ignore" });
  let error, stopped = false;
  child.once("error", e => { error = e; });
  child.once("exit", () => { stopped = true; });
  for (let i = 0; i < 300; i++) {
    try { const ready = JSON.parse((await fs.readFile(readyFile, "utf8")).replace(/^\uFEFF/, "")); if (ready.pid === child.pid) { child.unref(); return; } }
    catch {}
    if (error || stopped) throw Error("无法启动更新安装程序，归屿仍保持运行，请重试。");
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  child.kill();
  throw Error("更新安装程序准备超时，归屿仍保持运行，请重试。");
}
module.exports = { createInstallerUpdater };
