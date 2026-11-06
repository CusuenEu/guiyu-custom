"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const { spawn, execFileSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const repository = "tiduse1988/guiyu";
const baseline = "windows-20261103-01";
const release = "windows-20261106-01";

async function probe(fetch, label, address, options = {}) {
  try {
    const response = await fetch(address, { ...options, signal: AbortSignal.timeout(20000) });
    const location = response.headers.get("location");
    const hop = location ? new URL(location, address) : null;
    const safeURL = new URL(response.url || address);
    let error;
    if (response.status >= 400 && response.body) {
      const reader = response.body.getReader();
      const result = await reader.read();
      error = Buffer.from(result.value || []).toString("utf8").slice(0, 650)
        .replace(/https?:\/\/[^\s<>"]+/g, url => url.split("?")[0]);
      await reader.cancel();
    } else await response.body?.cancel();
    console.log(JSON.stringify({
      label, status: response.status, host: safeURL.hostname,
      redirect: hop?.hostname, expiry: hop?.searchParams.get("se"),
      type: response.headers.get("content-type"), server: response.headers.get("server"),
      cache: response.headers.get("x-cache"), via: response.headers.get("via"), error,
    }));
  } catch (error) {
    console.log(JSON.stringify({ label, error: error.message }));
  }
}

async function checks(fetch, urls, transport) {
  for (const [label, address, options] of [
    ["new canonical first hop", urls.new, { redirect: "manual" }],
    ["new canonical download", urls.new],
    ["new unique-query download", urls.new + "?guiyu_probe=" + Date.now()],
    ["previous canonical download", urls.old],
    ["new asset API download", urls.api, { headers: { Accept: "application/octet-stream" } }],
  ]) await probe(fetch, transport + " " + label, address, options);
}

async function run() {
  if (process.platform !== "win32" || process.env.CI !== "true") throw Error("Windows CI only");
  const repo = path.resolve(__dirname, "../..");
  const asar = require.resolve("@electron/asar", { paths: [path.join(repo, "Windows")] });
  const { createPackage } = await import(pathToFileURL(asar).href);
  const temp = await fs.mkdtemp(path.join(process.env.RUNNER_TEMP, "guiyu-download-diagnosis-"));
  try {
    const info = JSON.parse(execFileSync("gh", ["api", "repos/" + repository + "/releases/tags/" + release], { encoding: "utf8" }));
    const asset = info.assets.find(value => value.name.endsWith("-x64-setup.exe"));
    const old = "https://github.com/" + repository + "/releases/download/" + baseline + "/Guiyu-20261103-01-Windows-x64-setup.exe";
    const urls = { new: asset.browser_download_url, old, api: asset.url };
    await checks(fetch, urls, "Node");
    const archive = "Guiyu-20261103-01-Windows-x64.zip";
    execFileSync("gh", ["release", "download", baseline, "--repo", repository, "--pattern", archive, "--dir", temp],
      { stdio: "inherit", timeout: 180000 });
    execFileSync("tar.exe", ["-xf", path.join(temp, archive), "-C", temp]);
    const runtime = path.join(temp, "Guiyu-win32-x64");
    const shim = path.join(temp, "shim");
    await fs.mkdir(shim);
    await fs.writeFile(path.join(shim, "package.json"), JSON.stringify({ name: "guiyu-download-diagnosis", version: "1.0.0", main: "probe.cjs" }));
    await fs.writeFile(path.join(shim, "probe.cjs"), [
      "const {app,net}=require('electron');",
      probe.toString(), checks.toString(),
      "app.whenReady().then(()=>checks((url,options)=>net.fetch(url,options)," + JSON.stringify(urls) + ",'Electron')).then(()=>setImmediate(()=>app.quit())).catch(e=>{console.error(e);app.exit(1);});",
    ].join("\n"));
    const appAsar = path.join(runtime, "resources", "app.asar");
    await fs.rename(appAsar, appAsar + ".original");
    await createPackage(shim, appAsar);
    const env = { ...process.env };
    delete env.GH_TOKEN;
    delete env.GITHUB_TOKEN;
    await new Promise((resolve, reject) => {
      const child = spawn(path.join(runtime, "Guiyu.exe"), [], { env, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
      child.stdout.pipe(process.stdout);
      child.stderr.pipe(process.stderr);
      const timer = setTimeout(() => { child.kill(); reject(Error("Electron probe timed out")); }, 140000);
      child.once("error", error => { clearTimeout(timer); reject(error); });
      child.once("exit", code => { clearTimeout(timer); code === 0 ? resolve() : reject(Error("Electron probe exit " + code)); });
    });
  } finally {
    await fs.rm(temp, { recursive: true, force: true, maxRetries: 10, retryDelay: 250 });
  }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
