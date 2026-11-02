"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { createUpdater, selectUpdate } = require("../src/update.cjs");

const current = { date: "20261031", sequence: 4 };
function release(date = "20261031", sequence = 5, options = {}) {
  const tag = options.tag || `windows-${date}-${String(sequence).padStart(2, "0")}`;
  return { tag_name: tag, draft: false, prerelease: true,
    assets: (options.arches || ["ia32", "x64"]).flatMap(arch =>
      (options.formats || ["-setup.exe"]).map(format => {
        const name = `Guiyu-${date}-${String(sequence).padStart(2, "0")}-test-Windows-${arch}${format}`;
        return { name, state: "uploaded",
          browser_download_url: `https://github.com/tiduse1988/guiyu/releases/download/${tag}/${name}` };
      })) };
}
const mac = { tag_name: "v20261101-01", draft: false, prerelease: false,
  assets: [{ name: "Guiyu-20261101-01-macOS-arm64.zip", state: "uploaded" }] };
const response = batch => ({ ok: true, json: async () => batch });

test("Mac latest and Windows prerelease EXE reproduce the live release layout", () => {
  for (const arch of ["ia32", "x64"]) {
    const result = selectUpdate([mac, release()], current, arch);
    assert.equal(result.status, "available");
    assert.equal(result.version, "20261031(05)");
    assert.equal(result.kind, "installer");
    assert(result.url.endsWith(`Windows-${arch}-setup.exe`));
    assert(!result.url.includes("latest"));
  }
});

test("same/newer installed Windows version never offers reinstall or downgrade", () => {
  for (const installed of [{ date: "20261031", sequence: 5 }, { date: "20261101", sequence: 1 }]) {
    const result = selectUpdate([mac, release()], installed, "x64");
    assert.equal(result.status, "current");
    assert.equal(result.url, undefined);
  }
});

test("selects numeric Windows versions across days/sequences, independent of API order", () => {
  const result = selectUpdate([release("20261031", 9), release("20261101", 1),
    release("20261031", 10)], current, "x64");
  assert.equal(result.version, "20261101(01)");
  assert.equal(selectUpdate([release("20261031", 9), release("20261031", 10)],
    current, "x64").version, "20261031(10)");
});

test("supports ZIP-only releases and prefers installer at the same version", () => {
  assert.equal(selectUpdate([release("20261031", 5, { formats: [".zip"] })],
    current, "ia32").kind, "zip");
  assert.equal(selectUpdate([release("20261031", 5, { formats: [".zip", "-setup.exe"] })],
    current, "x64").kind, "installer");
  assert.equal(selectUpdate([release(), release("20261101", 1, { formats: [".zip"] })],
    current, "x64").version, "20261101(01)");
});

test("ignores drafts, wrong architectures, incomplete or unofficial assets", () => {
  const draft = { ...release("20261101", 1), draft: true };
  const incomplete = release("20261101", 2);
  incomplete.assets.forEach(a => a.state = "new");
  const spoofed = release("20261101", 3);
  spoofed.assets.forEach(a => a.browser_download_url = "https://example.org/setup.exe");
  const badName = release("20261101", 4);
  badName.assets.forEach(a => a.name += ".bak");
  const wrongArch = release("20261101", 5, { arches: ["ia32"] });
  assert.equal(selectUpdate([draft, incomplete, spoofed, badName, wrongArch, mac],
    current, "x64").status, "unavailable");
  assert.throws(() => selectUpdate([release()], current, "arm64"), /架构/);
});

test("queries all release pages including prereleases, then opens the selected asset only on request", async () => {
  const calls = [], opened = [];
  const updater = createUpdater({ current, arch: "ia32",
    fetch: async (url, options) => {
      calls.push({ url, options });
      return response(calls.length === 1 ? Array(100).fill(mac) : [release()]);
    }, openExternal: async url => opened.push(url) });
  await assert.rejects(updater.download(), /先检查/);
  const result = await updater.check();
  assert.equal(result.status, "available");
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, "https://api.github.com/repos/tiduse1988/guiyu/releases?per_page=100&page=1");
  assert(calls[1].url.endsWith("page=2"));
  assert.equal(calls[0].options.signal, calls[1].options.signal);
  assert.deepEqual(opened, []);
  await updater.download();
  assert.deepEqual(opened, [result.url]);
});

test("failed recheck clears an earlier available download and supports retry", async () => {
  let count = 0;
  const updater = createUpdater({ current, arch: "x64", openExternal: async () => {},
    fetch: async () => ++count === 2 ? { ok: false, status: 403 } : response([release()]) });
  assert.equal((await updater.check()).status, "available");
  await assert.rejects(updater.check(), /访问受限/);
  await assert.rejects(updater.download(), /先检查/);
  assert.equal((await updater.check()).status, "available");
});

test("network, malformed API and HTTP failures stay errors rather than claiming up to date", async () => {
  for (const [fetch, expected] of [
    [async () => { throw Error("offline"); }, /无法连接/],
    [async () => ({ ok: false, status: 500 }), /500/],
    [async () => response({ message: "unexpected" }), /格式异常/],
    [async () => ({ ok: true, json: async () => { throw Error("invalid JSON"); } }), /无法连接/],
  ]) {
    const updater = createUpdater({ fetch, current, arch: "x64", openExternal: async () => {} });
    await assert.rejects(updater.check(), expected);
    await assert.rejects(updater.download(), /先检查/);
  }
});

test("timeout cancels the release request and gives a retryable error", async () => {
  const keepAlive = setInterval(() => {}, 1000);
  try {
    const updater = createUpdater({ current, arch: "x64", timeout: 10,
      openExternal: async () => {},
      fetch: (url, { signal }) => new Promise((resolve, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      }) });
    await assert.rejects(updater.check(), /超时/);
  } finally { clearInterval(keepAlive); }
});

test("main-process IPC dispatch uses the Windows updater and its matching download", async () => {
  const opened = [], requested = [];
  const electron = { app: { whenReady: () => ({ then() {} }),
    on() {}, requestSingleInstanceLock: () => true },
    net: { fetch: async url => { requested.push(url); return response([mac, release()]); } },
    shell: { openExternal: async url => opened.push(url) } };
  const context = vm.createContext({ process: { arch: "ia32", env: {} },
    require: name => name === "electron" ? electron :
      name === "../version.json" ? current :
      name === "./update.cjs" ? require("../src/update.cjs") :
      name.startsWith("./") ? {} : require(name) });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  const result = await vm.runInContext('dispatch("checkUpdate")', context);
  assert.equal(result.status, "available");
  await vm.runInContext('dispatch("downloadUpdate", {url:"https://example.org"})', context);
  assert.deepEqual(opened, [result.url]);
  assert(opened[0].endsWith("Windows-ia32-setup.exe"));
  assert(!requested[0].includes("latest"));
});

function updateUI(invoke) {
  const button = { textContent: "检查更新" }, status = { setAttribute() {} };
  const source = fs.readFileSync(path.join(__dirname, "../src/ui.cjs"), "utf8").replace(/\r\n/g, "\n");
  const start = source.indexOf('  const updateButton = $("#check-update")');
  const end = source.indexOf("\n}\nfunction categoryList", start);
  assert(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), {
    $: selector => selector === "#check-update" ? button : status, api: invoke,
  });
  return { button, status };
}

test("settings checks before downloading and handles browser-open failure with retry", async () => {
  const calls = [];
  const { button, status } = updateUI(async method => {
    calls.push(method);
    if (method === "checkUpdate") return { status: "available", message: "发现新版" };
    if (calls.length === 2) throw Error("浏览器打开失败");
    return true;
  });
  const checking = button.onclick();
  assert.equal(button.disabled, true);
  assert.equal(button.textContent, "正在检查…");
  await checking;
  assert.equal(button.textContent, "下载更新");
  assert.deepEqual(calls, ["checkUpdate"]);
  await button.onclick();
  assert.equal(status.textContent, "浏览器打开失败");
  assert.equal(button.disabled, false);
  await button.onclick();
  assert.match(status.textContent, /已打开 Windows 下载/);
  assert.deepEqual(calls, ["checkUpdate", "downloadUpdate", "downloadUpdate"]);
});

test("settings leaves the check button available after no update or request failure", async () => {
  let calls = 0;
  const { button, status } = updateUI(async () => {
    if (++calls === 1) throw Error("网络失败");
    return { status: "current", message: "已是最新发布版本" };
  });
  await button.onclick();
  assert.equal(status.textContent, "网络失败");
  assert.equal(button.disabled, false);
  assert.equal(button.textContent, "检查更新");
  await button.onclick();
  assert.equal(status.textContent, "已是最新发布版本");
  assert.equal(button.textContent, "检查更新");
});
