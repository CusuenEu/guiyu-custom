"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), vm = require("node:vm");
const core = require("../src/core.cjs");

async function fixture(t) {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-name-archive-")));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const inbox = path.join(dir, "桌面"), root = path.join(dir, "项目库"), project = path.join(root, "2026", "合同项目");
  await fs.mkdir(inbox); await fs.mkdir(project, { recursive: true });
  const store = await new core.Store(path.join(dir, "state")).init([{ id: "desktop", path: inbox, kind: "folder" }]);
  await store.addRoots([root]);
  const context = vm.createContext({ process,
    __dirname: path.resolve(__dirname, "../src"),
    require: name => name === "electron" ? { app: { whenReady: () => ({ then() {} }), on() {}, requestSingleInstanceLock: () => true } } :
      name === "./core.cjs" ? core : name === "./documents.cjs" ? { extract: async () => "" } :
      name === "./update.cjs" ? { createUpdater: () => ({}) } :
      name === "../version.json" ? require("../version.json") :
      name.startsWith("./") ? require(path.resolve(__dirname, "../src", name)) : require(name) });
  vm.runInContext(await fs.readFile(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  context.fixtureStore = store;
  vm.runInContext("store = fixtureStore", context);
  async function dispatch(method, arg) {
    context.args = arg;
    return vm.runInContext(`dispatch(${JSON.stringify(method)}, args)`, context);
  }
  return { dir, inbox, project, store, dispatch };
}

test("rename-and-archive prepares current document metadata, moving only after archive confirmation", async t => {
  const f = await fixture(t), file = path.join(f.inbox, "旧名称.PDF");
  await fs.writeFile(file, "original content");
  const original = await core.entry(file);
  const result = await f.dispatch("rename", { forArchive: true, plans: [{ entry: original, name: "合同名称.PDF" }] });
  assert.equal(result.result, 1); assert.equal(result.renamedItems.length, 1);
  const renamed = result.renamedItems[0];
  assert.equal(renamed.path, path.join(f.inbox, "合同名称.PDF"));
  assert.equal(renamed.identity, original.identity);
  await core.verify(renamed);
  assert.equal(await fs.readFile(renamed.path, "utf8"), "original content");
  assert.equal(f.store.settings.moves.length, 0);
  await assert.rejects(fs.stat(path.join(f.project, renamed.name)), { code: "ENOENT" });
  const archived = await f.dispatch("archive", { items: result.renamedItems, destination: f.project });
  assert.equal(archived.result, 1);
  assert.equal(await fs.readFile(path.join(f.project, renamed.name), "utf8"), "original content");
  await assert.rejects(fs.stat(renamed.path), { code: "ENOENT" });
});

test("folders retain children and fresh identity; only submitted batch items are prepared", async t => {
  const f = await fixture(t), folder = path.join(f.inbox, "原文件夹"), skipped = path.join(f.inbox, "跳过.txt");
  await fs.mkdir(folder); await fs.writeFile(path.join(folder, "内部.txt"), "child"); await fs.writeFile(skipped, "skip");
  const result = await f.dispatch("rename", { forArchive: true, plans: [{ entry: await core.entry(folder), name: "合同文件夹" }] });
  assert.equal(result.renamedItems[0].folder, true);
  assert.equal(await fs.readFile(path.join(result.renamedItems[0].path, "内部.txt"), "utf8"), "child");
  assert.equal(await fs.readFile(skipped, "utf8"), "skip");
  assert.equal(result.renamedItems.length, 1);
  await f.dispatch("archive", { items: result.renamedItems, destination: f.project });
  assert.equal(await fs.readFile(path.join(f.project, "合同文件夹", "内部.txt"), "utf8"), "child");
});

test("unchanged names still prepare validated items for archiving without a rename record", async t => {
  const f = await fixture(t), file = path.join(f.inbox, "保留原名.txt");
  await fs.writeFile(file, "unchanged");
  const original = await core.entry(file);
  const result = await f.dispatch("rename", { forArchive: true, plans: [{ entry: original, name: original.name }] });
  assert.equal(result.result, 0);
  assert.equal(result.renamedItems[0].path, file);
  await core.verify(result.renamedItems[0]);
  assert.equal(f.store.settings.renames.length, 0);
  assert.equal(f.store.settings.moves.length, 0);
});

test("right-click external items transfer only their existing temporary permission to the new path", async t => {
  const f = await fixture(t), file = path.join(f.dir, "外部文件.txt"), other = path.join(f.dir, "其他文件.txt");
  await fs.writeFile(file, "external"); await fs.writeFile(other, "not granted");
  const key = p => process.platform === "win32" ? p.toLowerCase() : p;
  f.store.externalAllowed = new Set([key(file)]);
  const result = await f.dispatch("rename", { forArchive: true, plans: [{ entry: await core.entry(file), name: "外部新名称.txt" }] });
  await f.store.guard(result.renamedItems[0].path);
  assert(!f.store.externalAllowed.has(key(file)));
  await assert.rejects(f.store.guard(other), /范围/);
  await f.dispatch("archive", { items: result.renamedItems, destination: f.project });
  assert.equal(await fs.readFile(path.join(f.project, "外部新名称.txt"), "utf8"), "external");
});

test("collisions and stale selections stop before archive preparation or any move", async t => {
  const f = await fixture(t), file = path.join(f.inbox, "原文件.txt"), occupied = path.join(f.inbox, "同名.txt");
  await fs.writeFile(file, "original"); await fs.writeFile(occupied, "occupied");
  const original = await core.entry(file);
  await assert.rejects(f.dispatch("rename", { forArchive: true, plans: [{ entry: original, name: "同名.txt" }] }), /重复/);
  await fs.writeFile(file, "changed by another program");
  await assert.rejects(f.dispatch("rename", { forArchive: true, plans: [{ entry: original, name: "新文件.txt" }] }), /已更新|被替换/);
  assert.equal(f.store.settings.moves.length, 0);
  assert.equal(f.store.settings.renames.length, 0);
});

test("partial batch failure is reported without archive preparation and regular rename stays compatible", async t => {
  const f = await fixture(t), first = path.join(f.inbox, "一.txt"), second = path.join(f.inbox, "二.txt");
  await fs.writeFile(first, "one"); await fs.writeFile(second, "two");
  const save = f.store.save.bind(f.store);
  f.store.save = async () => { throw Error("configuration locked"); };
  await assert.rejects(f.dispatch("rename", { forArchive: true, plans: [
    { entry: await core.entry(first), name: "新一.txt" }, { entry: await core.entry(second), name: "新二.txt" },
  ] }), /已完成 1 项/);
  assert.equal(await fs.readFile(path.join(f.inbox, "新一.txt"), "utf8"), "one");
  assert.equal(await fs.readFile(second, "utf8"), "two");
  assert.equal(f.store.settings.moves.length, 0);
  f.store.save = save;
  const result = await f.dispatch("rename", { plans: [{ entry: await core.entry(second), name: "新二.txt" }] });
  assert.equal(result.result, 1);
  assert.equal(result.renamedItems, undefined);
});
