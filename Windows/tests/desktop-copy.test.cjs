"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const vm = require("node:vm");
const { defaults, migrate } = require("../src/source-defaults.cjs");
const { Store, entry, verify, runPS } = require("../src/core.cjs");

test("Windows default sources use the OS Downloads and Desktop locations", () => {
  const sources = defaults(name => `C:\\Users\\小王\\OneDrive\\${name}`);
  assert.deepEqual(sources.map(s => s.id), ["downloads", "desktop"]);
  assert.equal(sources[1].name, "桌面");
  assert.equal(sources[1].kind, "folder");
  assert.equal(sources[1].path, "C:\\Users\\小王\\OneDrive\\desktop");
});

test("legacy Recent migrates once in place, preserving custom entries and explicit removals", () => {
  const [downloads, desktop] = defaults(name => name);
  const custom = { id: "custom", path: "other", name: "合同", kind: "folder" };
  const old = [downloads, { id: "recent", kind: "recent", name: "最近使用" }, custom];
  const next = migrate(old, desktop);
  assert.deepEqual(next, [downloads, desktop, custom]);
  assert.equal(next[2], custom);
  assert.equal(old[1].id, "recent");
  assert.equal(migrate(next, desktop), next);
  assert.deepEqual(migrate([...old, desktop], desktop), [downloads, custom, desktop]);
  assert.equal(migrate([custom], desktop)[0], custom);
  assert.deepEqual(migrate([{ ...desktop, path: "old" }], desktop), [desktop]);
});

async function fixture(t) {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-desktop-copy-")));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const desktop = path.join(dir, "桌面 中文 $ space"), downloads = path.join(dir, "下载");
  await fs.mkdir(desktop); await fs.mkdir(downloads);
  const sources = defaults(name => name === "desktop" ? desktop : downloads);
  const store = await new Store(path.join(dir, "settings")).init(sources);
  const file = path.join(desktop, "合同 $1.txt"), folder = path.join(desktop, "项目 文件夹");
  await fs.writeFile(file, "original"); await fs.mkdir(folder);
  return { dir, desktop, sources, store, file, folder };
}

test("Desktop migration persists with settings and its real files stay in copy/archive scope", async t => {
  const f = await fixture(t);
  const old = { ...f.store.settings, sources: [f.sources[0], { id: "recent", kind: "recent" }], moves: [{ id: "history" }] };
  await f.store.save(old);
  const loaded = await new Store(f.store.stateDir).init(f.sources);
  await loaded.save({ ...loaded.settings, sources: migrate(loaded.settings.sources, f.sources[1]) });
  const reopened = await new Store(f.store.stateDir).init(f.sources);
  assert.equal(reopened.settings.sources[1].id, "desktop");
  assert.deepEqual(reopened.settings.moves, [{ id: "history" }]);
  assert.equal((await reopened.guard(f.file)).name, "合同 $1.txt");
  assert.equal((await reopened.guard(f.folder)).folder, true);
  await assert.rejects(reopened.guard(f.dir), /范围/);
});

test("copy IPC validates every selected file before touching the native clipboard", async t => {
  const f = await fixture(t), calls = [];
  const context = vm.createContext({ process: { platform: "win32", arch: "x64", env: {} },
    require: name => name === "electron" ? { app: { whenReady: () => ({ then() {} }), on() {}, requestSingleInstanceLock: () => true } } :
      name === "./core.cjs" ? { verify, runPS: async (script, env) => calls.push({ script, env }) } :
      name === "./update.cjs" ? { createUpdater: () => ({}) } :
      name === "../version.json" ? {} : name.startsWith("./") ? {} : require(name), __dirname: path.resolve(__dirname, "../src") });
  vm.runInContext(await fs.readFile(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  context.copyStore = f.store;
  vm.runInContext("store = copyStore", context);
  context.items = [await entry(f.file), await entry(f.folder)];
  const result = await vm.runInContext('dispatch("copyFiles", {items})', context);
  assert.equal(result.count, 2);
  assert.deepEqual(JSON.parse(calls[0].env.GUIYU_COPY_PATHS), [f.file, f.folder]);
  assert.match(calls[0].script, /SetFileDropList/);
  assert.equal(await fs.readFile(f.file, "utf8"), "original");
  await fs.writeFile(f.file, "changed after selection");
  await assert.rejects(vm.runInContext('dispatch("copyFiles", {items})', context), /已更新|被替换/);
  assert.equal(calls.length, 1);
  await assert.rejects(vm.runInContext('dispatch("copyFiles", {items:[]})', context), /请选择/);
});

test("Ctrl+C copies file selections, leaving text fields, editable text and dialogs untouched", async () => {
  const src = (await fs.readFile(path.join(__dirname, "../src/ui.cjs"), "utf8")).replace(/\r\n/g, "\n");
  const start = src.indexOf('document.addEventListener("keydown", (e) => {');
  const end = src.indexOf('\nwindow.guiyu?.onCommand', start);
  let callback, modalOpen = false, calls = [], prevented = 0;
  const context = { document: { activeElement: { id: "files" }, addEventListener: (name, fn) => { callback = fn; } },
    $: () => ({ open: modalOpen }), action: fn => fn(), api: async (method, arg) => { calls.push({ method, arg }); return { count: 2 }; },
    toast() {}, selectedItems: () => [{ path: "file" }, { path: "folder" }], source: null, project: null };
  vm.runInNewContext(src.slice(start, end), context);
  const event = target => ({ key: "c", ctrlKey: true, target, preventDefault: () => { prevented++; } });
  callback(event({ tagName: "DIV", closest: () => null }));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.length, 1); assert.equal(calls[0].method, "copyFiles"); assert.equal(prevented, 1);
  for (const tagName of ["INPUT", "TEXTAREA", "SELECT"])
    callback(event({ tagName }));
  callback(event({ tagName: "DIV", isContentEditable: true }));
  modalOpen = true; callback(event({ tagName: "DIV" }));
  assert.equal(calls.length, 1); assert.equal(prevented, 1);
});

test("native clipboard retains a file/folder list and Copy effect after writer exits", { skip: process.platform !== "win32" }, async t => {
  const f = await fixture(t);
  const script = await fs.readFile(path.join(__dirname, "../scripts/copy-files.ps1"), "utf8");
  await runPS(script, { GUIYU_COPY_PATHS: JSON.stringify([f.file, f.folder]) }, 15000);
  const result = JSON.parse(await runPS("[Console]::OutputEncoding=[Text.Encoding]::UTF8;Add-Type -AssemblyName System.Windows.Forms;$d=[Windows.Forms.Clipboard]::GetDataObject();$e=$d.GetData('Preferred DropEffect');$bytes=$e.ToArray();ConvertTo-Json -Compress @{paths=@([Windows.Forms.Clipboard]::GetFileDropList());effect=[int]$bytes[0]}", {}, 15000));
  assert.deepEqual(result.paths, [f.file, f.folder]);
  assert.equal(result.effect, 1);
  assert.equal(await fs.readFile(f.file, "utf8"), "original");
});
