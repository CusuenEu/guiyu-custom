"use strict";
// Install the public baseline, drive its settings UI, and observe its own
// updater. The running app and its network requests are never replaced.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const net = require("node:net");
const path = require("node:path");
const { createReadStream } = require("node:fs");
const { execFileSync, spawn } = require("node:child_process");
const { setTimeout: delay } = require("node:timers/promises");
const version = require("../version.json");

const previous = "windows-20261103-01";
const previousVersion = "2026.1103.1";
const previousDisplay = "20261103(01)";
const arch = process.argv[2];
const repository = "tiduse1988/guiyu";
const current = "windows-" + version.assetPrefix.slice("Guiyu-".length);
const exeName = "Guiyu.exe";

function powershell(script) {
  return execFileSync("powershell.exe", [
    "-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64"),
  ], { encoding: "utf8", timeout: 120_000, windowsHide: true }).trim();
}

const quote = value => "'" + value.replace(/'/g, "''") + "'";
const readJSON = async file => JSON.parse((await fs.readFile(file, "utf8")).replace(/^\uFEFF/, ""));

function releaseAsset(tag, name) {
  const release = JSON.parse(execFileSync("gh", ["api", `repos/${repository}/releases/tags/${tag}`], { encoding: "utf8" }));
  assert.equal(release.draft, false);
  assert.equal(release.prerelease, false);
  const asset = release.assets.find(candidate => candidate.name === name);
  assert(asset, `Missing public asset ${name}`);
  assert.equal(asset.state, "uploaded");
  assert.match(asset.digest, /^sha256:[a-f0-9]{64}$/);
  return asset;
}

async function sha256(file) {
  const hash = crypto.createHash("sha256");
  for await (const bytes of createReadStream(file)) hash.update(bytes);
  return hash.digest("hex");
}

async function waitFor(description, timeout, read) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await read();
    if (value) return value;
    await delay(250);
  }
  throw Error(`Timed out waiting for ${description}`);
}

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address();
  await new Promise(resolve => server.close(resolve));
  return port;
}

async function connect(url) {
  const socket = new WebSocket(url);
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { socket.close(); reject(Error("DevTools connection timed out")); }, 5000);
    socket.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
    socket.addEventListener("error", () => { clearTimeout(timeout); reject(Error("DevTools connection failed")); }, { once: true });
  });
  let id = 0;
  const pending = new Map();
  socket.addEventListener("message", event => {
    const reply = JSON.parse(event.data);
    const request = pending.get(reply.id);
    if (!request) return;
    pending.delete(reply.id);
    clearTimeout(request.timeout);
    if (reply.error || reply.result.exceptionDetails) {
      request.reject(Error(JSON.stringify(reply.error || reply.result.exceptionDetails)));
    } else request.resolve(reply.result.result.value);
  });
  socket.addEventListener("close", () => {
    for (const request of pending.values()) {
      clearTimeout(request.timeout);
      request.reject(Error("Client window closed"));
    }
    pending.clear();
  });
  return {
    close: () => socket.close(),
    evaluate(expression) {
      if (socket.readyState !== WebSocket.OPEN) return Promise.reject(Error("Client window closed"));
      return new Promise((resolve, reject) => {
        const request = ++id;
        const timeout = setTimeout(() => {
          pending.delete(request);
          reject(Error("Client UI evaluation timed out"));
        }, 5000);
        pending.set(request, { resolve, reject, timeout });
        socket.send(JSON.stringify({
          id: request, method: "Runtime.evaluate", params: { expression, returnByValue: true },
        }));
      });
    },
  };
}

function productVersion(exe) {
  return powershell(`(Get-Item -LiteralPath ${quote(exe)}).VersionInfo.ProductVersion`).replace(/\.0$/, "");
}

async function verifyArchitecture(exe) {
  const handle = await fs.open(exe, "r");
  try {
    const dos = Buffer.alloc(64), pe = Buffer.alloc(6);
    await handle.read(dos, 0, dos.length, 0);
    assert.equal(dos.toString("ascii", 0, 2), "MZ");
    await handle.read(pe, 0, pe.length, dos.readUInt32LE(60));
    assert.equal(pe.readUInt32LE(0), 0x4550);
    assert.equal(pe.readUInt16LE(4), arch === "x64" ? 0x8664 : 0x014c);
  } finally {
    await handle.close();
  }
}

async function run() {
  assert(process.platform === "win32" && process.env.CI === "true" && process.env.RUNNER_TEMP, "Disposable Windows CI only");
  assert(["ia32", "x64"].includes(arch), "Expected ia32 or x64");
  const { extractFile } = await import("@electron/asar");
  const temp = await fs.mkdtemp(path.join(process.env.RUNNER_TEMP, `guiyu-public-${arch}-`));
  const installDir = path.join(temp, "归屿 正式安装");
  const executable = path.join(installDir, exeName);
  const asar = path.join(installDir, "resources", "app.asar");
  let old, client, status, updateDir, helperPid, oldExit, oldError, updateText = "";
  try {
    const oldName = `Guiyu-20261103-01-Windows-${arch}-setup.exe`;
    const oldAsset = releaseAsset(previous, oldName);
    const newAsset = releaseAsset(current, `${version.assetPrefix}-Windows-${arch}-setup.exe`);
    execFileSync("gh", ["release", "download", previous, "--repo", repository, "--pattern", oldName, "--dir", temp],
      { stdio: "inherit", timeout: 240_000 });
    const oldInstaller = path.join(temp, oldName);
    assert.equal((await fs.stat(oldInstaller)).size, oldAsset.size);
    assert.equal(await sha256(oldInstaller), oldAsset.digest.slice(7));
    powershell(`$p=Start-Process -FilePath ${quote(oldInstaller)} -ArgumentList ${quote("/S /D=" + installDir)} -PassThru -Wait; exit $p.ExitCode`);
    assert.equal(productVersion(executable), previousVersion);
    assert.equal(JSON.parse(extractFile(asar, "version.json")).display, previousDisplay);
    await verifyArchitecture(executable);
    const oldHash = await sha256(asar);
    console.log(`PASS ${arch}: installed verified official baseline ${previousDisplay}`);

    const port = await freePort();
    const env = { ...process.env, TMP: temp, TEMP: temp };
    delete env.GH_TOKEN;
    delete env.GITHUB_TOKEN;
    delete env.GUIYU_REVIEW;
    old = spawn(executable, [`--remote-debugging-port=${port}`, "--remote-debugging-address=127.0.0.1",
      `--user-data-dir=${path.join(temp, "browser-profile")}`], {
      cwd: installDir, env, windowsHide: true, stdio: "ignore",
    });
    old.once("exit", code => { oldExit = code; });
    old.once("error", error => { oldError = error; });
    const url = await waitFor("official client's window", 45_000, async () => {
      if (oldError) throw oldError;
      if (oldExit !== undefined) throw Error(`Official client exited before update: ${oldExit}`);
      const response = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: AbortSignal.timeout(1000) }).catch(() => null);
      if (!response?.ok) return null;
      return (await response.json()).find(target => target.type === "page" && target.url.endsWith("/src/index.html"))?.webSocketDebuggerUrl;
    });
    client = await connect(url);
    await waitFor("workspace ready", 45_000, () => client.evaluate("Boolean(document.querySelector('#settings') && typeof data !== 'undefined' && data)"));
    await client.evaluate("document.querySelector('#settings').click()");
    assert(await client.evaluate(`document.querySelector('.version').textContent.includes(${JSON.stringify(previousDisplay)})`));
    await client.evaluate("document.querySelector('#check-update').click()");
    await waitFor("public update check", 45_000, async () => {
      const info = await client.evaluate("({label:document.querySelector('#check-update').textContent,status:document.querySelector('#update-status').textContent})");
      updateText = info.status;
      if (info.label === "正在检查…") return false;
      assert.equal(info.label, "更新并重启", info.status);
      assert(info.status.includes(version.display), info.status);
      return true;
    });
    console.log(`PASS ${arch}: ${previousDisplay} discovered ${version.display} through the built-in update check`);
    await client.evaluate("document.querySelector('#check-update').click()");

    await waitFor("verified download, install, and restart", 12 * 60_000, async () => {
      if (oldExit !== undefined && oldExit !== 0) throw Error(`Old client exited with ${oldExit}`);
      updateDir ??= (await fs.readdir(temp)).find(name => name.startsWith("Guiyu-update-"));
      if (updateDir) {
        const dir = path.join(temp, updateDir);
        helperPid ??= (await readJSON(path.join(dir, "ready.json")).catch(() => null))?.pid;
        status = await readJSON(path.join(dir, "status.json")).catch(() => status);
        if (status?.phase === "failed") throw Error(status.message);
        if (status?.phase === "completed") return true;
      }
      if (oldExit === undefined) {
        const ui = await client.evaluate("({text:document.querySelector('#update-status').textContent,enabled:!document.querySelector('#check-update').disabled})").catch(() => null);
        if (ui?.text !== undefined) {
          updateText = ui.text;
          if (ui.enabled) throw Error(`The updater returned without installing: ${ui.text}`);
        }
      }
      return false;
    });

    const manifest = await readJSON(path.join(temp, updateDir, "manifest.json"));
    assert.equal(manifest.parentPid, old.pid);
    assert.equal(manifest.digest, newAsset.digest.slice(7));
    assert.equal(manifest.packageVersion, version.packageVersion);
    assert.equal(manifest.executable.toLowerCase(), executable.toLowerCase());
    await waitFor("old client exit", 10_000, () => oldExit !== undefined);
    assert.equal(oldExit, 0);
    assert(status.processId > 0 && status.processId !== old.pid);
    await waitFor("replacement window", 45_000, () => {
      const window = powershell(`$p=Get-Process -Id ${status.processId} -ErrorAction SilentlyContinue; if($p -and $p.MainWindowHandle -ne 0){$p.Path}`);
      return window.toLowerCase() === executable.toLowerCase();
    });
    assert.equal(productVersion(executable), version.packageVersion);
    assert.equal(JSON.parse(extractFile(asar, "version.json")).display, version.display);
    assert.notEqual(await sha256(asar), oldHash);
    await verifyArchitecture(executable);
    console.log(`PASS ${arch}: public ${previousDisplay} → ${version.display}; live download verified against release SHA256, silent install and new window, no manual new installer`);
  } catch (error) {
    console.error({ arch, oldExit, oldPid: old?.pid, status, updateText });
    if (updateDir) {
      const log = await fs.readFile(path.join(temp, updateDir, "helper.log"), "utf8").catch(() => "");
      if (log) console.error(log.slice(-4000));
    }
    throw error;
  } finally {
    client?.close();
    for (const pid of [status?.processId, helperPid, oldExit === undefined ? old?.pid : null].filter(Boolean)) {
      try { execFileSync("taskkill.exe", ["/PID", String(pid), "/T", "/F"], { stdio: "ignore", timeout: 10_000 }); } catch {}
    }
    const uninstall = path.join(installDir, "卸载归屿.exe");
    if (await fs.stat(uninstall).catch(() => null)) {
      powershell(`$p=Start-Process -FilePath ${quote(uninstall)} -ArgumentList '/S' -PassThru -Wait; exit $p.ExitCode`);
    }
    await fs.rm(temp, { recursive: true, force: true, maxRetries: 12, retryDelay: 250 });
  }
}

run().catch(error => { console.error(error); process.exitCode = 1; });
