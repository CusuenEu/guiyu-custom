"use strict";
const fs = require("node:fs/promises"), path = require("node:path"), crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { setTimeout: delay } = require("node:timers/promises");

const downloadAttempts = 3;
const retryableStatuses = new Set([400, 408, 429, 500, 502, 503, 504]);

async function downloadInstaller(fetch, update, installer, progress) {
  const file = await fs.open(installer, "wx");
  let size = 0, hash = crypto.createHash("sha256"), notified = 0;
  const report = () => progress({ phase: "downloading", percent: Math.floor(size / update.size * 100) });
  async function reset() {
    await file.truncate(0);
    size = 0;
    hash = crypto.createHash("sha256");
    report();
  }

  try {
    report();
    for (let attempt = 0; attempt < downloadAttempts; attempt++) {
      if (attempt) {
        progress({ phase: "retrying", percent: Math.floor(size / update.size * 100) });
        await delay(750 * attempt);
      }
      const url = new URL(update.url);
      if (attempt) url.searchParams.set("guiyu-retry", crypto.randomUUID());
      const headers = size ? { Range: `bytes=${size}-` } : {};
      let response;
      try {
        response = await fetch(url.href, { headers, signal: AbortSignal.timeout(10 * 60 * 1000) });
      } catch (error) {
        if (attempt + 1 === downloadAttempts) throw error;
        continue;
      }
      if (!response.ok || !response.body) {
        await response.body?.cancel().catch(() => {});
        if (attempt + 1 < downloadAttempts) {
          if (response.status === 416 && size) {
            await reset();
            continue;
          }
          if (retryableStatuses.has(response.status)) continue;
        }
        throw Error(`更新包下载失败（${response.status}），请重试。`);
      }
      let limit = update.size;
      if (response.status === 206) {
        const range = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get("content-range") || "");
        const [, start, end, total] = (range || []).map(Number);
        if (!range || start !== size || end < start || end >= update.size || total !== update.size) {
          await response.body.cancel().catch(() => {});
          throw Error("更新包续传范围异常，已停止安装。");
        }
        limit = end + 1;
      } else if (response.status !== 200) {
        await response.body.cancel().catch(() => {});
        throw Error(`更新包下载失败（${response.status}），请重试。`);
      } else if (size) {
        await reset(); // A server may ignore Range and return the complete package.
      }

      const reader = response.body.getReader();
      let interrupted;
      try {
        for (;;) {
          let next;
          try { next = await reader.read(); }
          catch (error) { interrupted = error; break; }
          if (next.done) break;
          const chunk = Buffer.from(next.value);
          if (size + chunk.length > limit) throw Error("更新包大小异常，已停止安装。");
          // Explicit positions also work after the server requires a fresh download.
          for (let offset = 0; offset < chunk.length;) {
            const { bytesWritten } = await file.write(chunk, offset, chunk.length - offset, size + offset);
            if (!bytesWritten) throw Error("更新包无法写入磁盘。");
            offset += bytesWritten;
          }
          hash.update(chunk);
          size += chunk.length;
          if (Date.now() - notified > 200) { report(); notified = Date.now(); }
        }
      } finally {
        await reader.cancel().catch(() => {});
        reader.releaseLock();
      }
      if (size === update.size) break;
      if (attempt + 1 === downloadAttempts)
        throw interrupted || Error("更新包下载不完整，请重试。");
    }
  } finally { await file.close(); }

  progress({ phase: "verifying" });
  if (size !== update.size || hash.digest("hex") !== update.digest.slice(7).toLowerCase())
    throw Error("更新包校验失败，已删除下载文件，请重新检查更新。");
}

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
      await downloadInstaller(fetch, update, installer, progress);
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
  const logFile = path.join(path.dirname(manifest), "helper.log");
  const literal = value => "'" + value.replace(/'/g, "''") + "'";
  const encode = value => Buffer.from(value, "utf16le").toString("base64");
  const command = encode(`& ${literal(helper)} -Manifest ${literal(manifest)} *> ${literal(logFile)}`);
  // Start-Process creates an independent Windows process with its own console.
  // Direct Electron children can lose their console when the old app quits;
  // Node's detached flag also breaks Windows PowerShell initialization on CI.
  const bootstrap = encode(`$ErrorActionPreference='Stop'; $env:PSModulePath=[IO.Path]::Combine($PSHOME,'Modules'); $p=Start-Process -FilePath ([IO.Path]::Combine($PSHOME,'powershell.exe')) -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand','${command}') -PassThru; @{pid=$p.Id}|ConvertTo-Json -Compress`);
  let error, stopped = false, exitCode, helperPid, output = "", diagnostic = "";
  const child = spawn("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", bootstrap],
    { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", chunk => { output = (output + chunk).slice(-4000); try { const result = JSON.parse(output.trim()); if (Number.isInteger(result.pid) && result.pid > 0) helperPid = result.pid; } catch {} });
  child.stderr.on("data", chunk => { diagnostic = (diagnostic + chunk).slice(-2000); });
  child.once("error", e => { error = e; });
  child.once("exit", code => { stopped = true; exitCode = code; });
  const stop = () => { if (helperPid) try { process.kill(helperPid); } catch {} if (!stopped) child.kill(); };
  for (let i = 0; i < 300; i++) {
    try { const ready = JSON.parse((await fs.readFile(readyFile, "utf8")).replace(/^\uFEFF/, "")); if (helperPid && ready.pid === helperPid) { child.unref(); return; } }
    catch {}
    let status;
    try { status = JSON.parse((await fs.readFile(path.join(path.dirname(manifest), "status.json"), "utf8")).replace(/^\uFEFF/, "")); } catch {}
    if (status?.phase === "failed") { stop(); throw Error(`更新助手未能准备就绪，旧程序仍在运行：${status.message}`); }
    if (error || (stopped && (exitCode !== 0 || !helperPid))) {
      const detail = error?.message || diagnostic || (await fs.readFile(logFile, "utf8").catch(() => "")).trim().slice(-1200);
      stop();
      throw Error(`无法启动更新安装程序（${exitCode ?? "启动失败"}），归屿仍保持运行：${detail}`);
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  stop();
  diagnostic ||= (await fs.readFile(logFile, "utf8").catch(() => "")).trim().slice(-1500);
  const readyText = (await fs.readFile(readyFile, "utf8").catch(() => "未生成就绪记录")).trim();
  throw Error(`更新安装程序准备超时，归屿仍保持运行：${diagnostic || `进程 ${child.pid}，${readyText}`}`);
}
module.exports = { createInstallerUpdater };
