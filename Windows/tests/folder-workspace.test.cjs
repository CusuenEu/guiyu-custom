"use strict";
const { test } = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs/promises"), os = require("node:os"), path = require("node:path");
const vm = require("node:vm");
const core = require("../src/core.cjs");
const { Store, entry, list } = require("../src/core.cjs");
async function fixture(t) {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-folders-")));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const downloads = path.join(dir, "下载"), root = path.join(downloads, "关联目录"), empty = path.join(dir, "空关联目录");
  await fs.mkdir(root, { recursive: true }); await fs.mkdir(empty);
  const store = await new Store(path.join(dir, "state")).init([{ id: "downloads", name: "下载", path: downloads, kind: "folder" }]);
  return { dir, downloads, root, empty, store };
}
test("a project location inside Downloads is linkable and its empty association is retained", async t => {
  const f = await fixture(t);
  await f.store.addRoots([f.root, f.empty]);
  assert.deepEqual(f.store.settings.roots, [f.root, f.empty]);
  assert.deepEqual(f.store.snapshot.rootEntries, []);
  assert.equal((await f.store.browse(f.root)).folder, true);
  assert.equal((await f.store.browse(f.empty)).folder, true);
  assert.deepEqual(await list(f.empty), []);
  const reopened = await new Store(f.store.stateDir).init();
  assert.deepEqual(reopened.settings.roots, [f.root, f.empty]);
});
test("root entries index direct folders and documents without flattening descendants", async t => {
  const f = await fixture(t), project = path.join(f.root, "项目"), nested = path.join(project, "附件");
  await fs.mkdir(nested, { recursive: true });
  await fs.writeFile(path.join(f.root, "根文档.txt"), "root");
  await fs.writeFile(path.join(project, "项目文档.txt"), "project");
  await fs.writeFile(path.join(nested, "深层.txt"), "nested");
  await f.store.addRoots([f.root]);
  assert.deepEqual(f.store.snapshot.rootEntries.map(e => e.name).sort(), ["根文档.txt", "项目"].sort());
  assert(f.store.snapshot.rootEntries.every(e => e.directory === f.root));
  const files = f.store.snapshot.rootFiles.filter(e => e.directory === f.root);
  assert.deepEqual(files.map(e => e.name).sort(), ["附件", "项目文档.txt"].sort());
  assert(files.every(e => e.project === project));
  assert(!files.some(e => e.name === "深层.txt"));
});
test("nested sources and sources inside project locations are views, not conflicting ownership", async t => {
  const f = await fixture(t), child = path.join(f.root, "待整理");
  await fs.mkdir(child); await f.store.addRoots([f.root]);
  await f.store.addSources([f.root, child, child]);
  assert.equal(f.store.settings.sources.filter(s => s.path === child).length, 1);
  assert.equal((await f.store.browse(child)).folder, true);
  await assert.rejects(f.store.browse(f.dir), /范围/);
  await assert.rejects(f.store.addRoots([child]), /嵌套/);
  await assert.rejects(f.store.rename([{ entry: await entry(f.root), name: "不能改关联根" }]), /总目录本身/);
});
test("a direct child folder of a linked project location is a valid archive target", async t => {
  const f = await fixture(t), project = path.join(f.root, "直接项目");
  await fs.mkdir(project); await f.store.addRoots([f.root]);
  const file = path.join(f.downloads, "待归档.txt"); await fs.writeFile(file, "data");
  await f.store.archive([await entry(file)], project);
  assert.equal(await fs.readFile(path.join(project, "待归档.txt"), "utf8"), "data");
});
test("renaming a selected middle folder keeps linked sources and sidebar order paths in sync", async t => {
  const f = await fixture(t), project = path.join(f.root, "原项目");
  await fs.mkdir(project); await f.store.addRoots([f.root]); await f.store.addSources([project]);
  await f.store.save({ ...f.store.settings, directoryOrders: { [f.root]: [project] } });
  await f.store.rename([{ entry: await entry(project), name: "新项目" }]);
  const renamed = path.join(f.root, "新项目");
  assert.equal(f.store.settings.sources.find(s => s.path === renamed).name, "新项目");
  assert.deepEqual(f.store.settings.directoryOrders[f.root], [renamed]);
  await f.store.refresh();
  assert(f.store.snapshot.rootEntries.some(e => e.path === renamed));
});
test("empty and missing associations remain distinguishable across refreshes", async t => {
  const f = await fixture(t); await f.store.addRoots([f.empty]);
  assert(!f.store.snapshot.unavailable.includes(f.empty));
  await fs.rmdir(f.empty); await f.store.refresh();
  assert(f.store.settings.roots.includes(f.empty));
  assert(f.store.snapshot.unavailable.includes(f.empty));
  await fs.mkdir(f.empty); await f.store.refresh();
  assert(!f.store.snapshot.unavailable.includes(f.empty));
});
test("real main-process association entrypoints permit sources and project locations to overlap", async t => {
  const f = await fixture(t), child = path.join(f.root, "再次关联");
  await fs.mkdir(child);
  let choice = f.root;
  const context = vm.createContext({ process,
    require: name => name === "electron" ? {
      app: { whenReady: () => ({ then() {} }), on() {}, requestSingleInstanceLock: () => true },
      dialog: { showOpenDialog: async () => ({ canceled: false, filePaths: [choice] }) },
    } : name === "./core.cjs" ? core : name === "./documents.cjs" ? {} :
      name === "./update.cjs" ? { createUpdater: () => ({}) } :
      name === "../version.json" ? require("../version.json") :
      name.startsWith("./") ? require(path.resolve(__dirname, "../src", name)) : require(name),
  });
  vm.runInContext(await fs.readFile(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  context.fixtureStore = f.store; vm.runInContext("store=fixtureStore", context);
  await vm.runInContext('dispatch("addRoots")', context);
  assert(f.store.settings.roots.includes(f.root));
  choice = child;
  await vm.runInContext('dispatch("addSource")', context);
  assert(f.store.settings.sources.some(s => s.path === child));
});
