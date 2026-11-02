"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), vm = require("node:vm");
const core = require("../src/core.cjs");

async function fixture(t, { defaultApp = false, startup = [] } = {}) {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-explorer-")));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const file = path.join(dir, "合同 中文 & $1.txt"), folder = path.join(dir, "项目 文件夹");
  await fs.writeFile(file, "original");
  for (const p of [folder, path.join(dir, "desktop"), path.join(dir, "downloads")]) await fs.mkdir(p);
  const store = await new core.Store(path.join(dir, "fixture-state")).init([]);
  const errors = [], sent = [], resolved = [], handlers = new Map();
  let lock, ready;
  const argv = [path.join(dir, "Guiyu.exe"), ...(defaultApp ? [path.join(dir, "src/main.cjs")] : []), ...startup.map(a => a === "FILE" ? file : a)];
  const window = { show() {}, focus() {}, loadFile() {},
    webContents: { send: (channel, command) => sent.push({ channel, command }),
      setWindowOpenHandler() {}, on() {}, session: { setPermissionRequestHandler() {} } } };
  const readyPromise = new Promise(resolve => { ready = resolve; });
  const electron = {
    app: { whenReady: () => readyPromise, on: (name, fn) => handlers.set(name, fn),
      requestSingleInstanceLock: data => { lock = data; return true; },
      getPath: name => ["downloads", "desktop"].includes(name) ? path.join(dir, name) : dir,
      quit() { throw Error("Unexpected application quit"); } },
    BrowserWindow: function () { return window; },
    dialog: { showErrorBox: (title, message) => errors.push({ title, message }) },
    ipcMain: { on() {}, handle() {} }, Menu: { setApplicationMenu() {} },
  };
  const context = vm.createContext({ process: { argv, defaultApp, platform: process.platform, arch: process.arch, env: {} },
    __dirname: path.resolve(__dirname, "../src"),
    require: name => name === "electron" ? electron :
      name === "node:fs/promises" ? { ...fs, realpath: p => { resolved.push(p); return fs.realpath(p); } } :
      name === "./core.cjs" ? core : name === "./documents.cjs" ? {} :
      name === "./update.cjs" ? { createUpdater: () => ({}) } :
      name === "./window-frame.cjs" ? { restore: () => null, attach() {}, minimum: { width: 1060, height: 700 } } :
      name === "../version.json" ? {} :
      name.startsWith("./") ? require(path.resolve(__dirname, "../src", name)) : require(name) });
  vm.runInContext(await fs.readFile(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  context.fixtureStore = store; context.fixtureWindow = window;
  vm.runInContext("store = fixtureStore; win = fixtureWindow", context);
  return { dir, file, folder, store, errors, sent, resolved, argv, lock, context,
    async incoming(args) { context.args = args; await vm.runInContext("incoming(args)", context); },
    async start() { ready(); await vm.runInContext("initialized", context); },
    second: (...args) => handlers.get("second-instance")(...args),
  };
}

test("Explorer naming/archive resolve only the selected path despite inserted/reordered Chromium switches", async t => {
  const f = await fixture(t);
  for (const type of ["--smart-name", "--smart-archive"]) {
    for (const selected of [f.file, f.folder]) {
      for (const args of [
        [f.argv[0], type, selected],
        [f.argv[0], type, "--allow-file-access-from-files", selected, "--original-process-start-time=123"],
        [f.argv[0], selected, "--original-process-start-time=123", type, "--allow-file-access-from-files"],
      ]) {
        await f.incoming(args);
        const result = f.sent.at(-1);
        assert.equal(result.channel, "guiyu-command");
        assert.equal(result.command.type, type);
        assert.equal(result.command.items[0].path, selected);
        assert.equal((await f.store.guard(selected)).path, selected);
      }
    }
  }
  assert.equal(f.sent.length, 12);
  assert.deepEqual(f.errors, []);
  assert(f.resolved.every(p => p === f.file || p === f.folder));
  await assert.rejects(f.store.guard(f.dir), /范围/);
  assert.equal(await fs.readFile(f.file, "utf8"), "original");
});

test("missing/ambiguous selection never resolves a switch or grants access to an unrelated file", async t => {
  const f = await fixture(t);
  await f.incoming([f.argv[0], "--allow-file-access-from-files"]);
  assert.equal(f.errors.length, 0);
  for (const tail of [
    ["--smart-name", "--allow-file-access-from-files"],
    ["--smart-archive", f.file, f.folder],
    ["--smart-name", "--smart-archive", f.file],
  ]) await f.incoming([f.argv[0], ...tail]);
  assert.equal(f.errors.length, 3);
  assert(f.errors.every(e => e.message.includes("唯一")));
  assert.deepEqual(f.resolved, []);
  assert.equal(f.sent.length, 0);
  assert.equal(f.store.externalAllowed?.size || 0, 0);
  const missing = path.join(f.dir, "已删除.txt");
  await f.incoming([f.argv[0], "--smart-name", missing]);
  assert.match(f.errors.at(-1).message, /ENOENT/);
  assert.equal(f.sent.length, 0);
});

test("cold startup and development mode exclude executable/application paths", async t => {
  for (const defaultApp of [false, true]) {
    const f = await fixture(t, { defaultApp, startup: ["--smart-name", "--allow-file-access-from-files", "FILE"] });
    await f.start();
    assert.equal(f.sent.length, 1);
    assert.equal(f.sent[0].command.items[0].path, f.file);
    assert.deepEqual(f.errors, []);
  }
});

test("second instance waits for initialization and prefers the original argv in additionalData", async t => {
  const f = await fixture(t);
  assert.equal(f.lock.argv, f.argv);
  const forwarded = [f.argv[0], "--smart-archive", f.folder];
  const pending = f.second({}, [f.argv[0], "--smart-name", f.file], f.dir, { argv: forwarded });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.sent.length, 0);
  await f.start(); await pending;
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].command.type, "--smart-archive");
  assert.equal(f.sent[0].command.items[0].path, f.folder);
  await f.second({}, [f.argv[0], f.file, "--smart-name", "--allow-file-access-from-files"], f.dir, {});
  assert.equal(f.sent.at(-1).command.items[0].path, f.file);
  assert.deepEqual(f.errors, []);
});
