"use strict";
const { test } = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), vm = require("node:vm");
const core = require("../src/core.cjs"), { moved } = require("../src/rail-order.cjs"), { rank } = require("../src/archive-match.cjs");
test("root containment works with a trailing root separator without accepting adjacent names", () => {
  const root = path.parse(process.cwd()).root;
  assert(core.inside(path.join(root, "项目", "A"), root));
  assert(core.inside(root, root));
  assert(!core.inside(path.join(root, "项目2"), path.join(root, "项目")));
});
test("whole drive association indexes direct files/folders and permits browsing its descendants", { skip: process.platform !== "win32" }, async t => {
  const temp = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-drive-")));
  t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const store = await new core.Store(path.join(temp, "state")).init([]), root = path.parse(temp).root;
  await store.addRoots([root]);
  assert.deepEqual(store.settings.roots, [root]);
  assert(store.snapshot.rootEntries.length > 0);
  assert(store.snapshot.rootEntries.every(e => e.directory === root && path.dirname(e.path) === root));
  assert.equal(store.snapshot.projects.length, 0, "A drive association must not scan every nested project");
  assert.equal((await store.guard(temp)).folder, true);
  await assert.rejects(store.rename([{ entry: await core.entry(root), name: "禁止改磁盘" }]), /范围|总目录/);
  await assert.rejects(store.addRoots([temp]), /嵌套/);
});
test("directory/root ordering supports before, after and last position without changing input", () => {
  const paths = ["A", "B", "C"];
  assert.deepEqual(moved(paths, "A", "C", true), ["B", "C", "A"]);
  assert.deepEqual(moved(paths, "C", "A", false), ["C", "A", "B"]);
  assert.deepEqual(moved(paths, "A", "B", true), ["B", "A", "C"]);
  assert.equal(moved(paths, "A", "A", true), null);
  assert.equal(moved(paths, "D", "A", false), null);
  assert.deepEqual(paths, ["A", "B", "C"]);
});
test("root and mixed file/folder order survive refresh/reopen; main rejects missing, duplicate and foreign paths", async t => {
  const temp = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-rail-")));
  t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const a = path.join(temp, "A"), b = path.join(temp, "B"), folder = path.join(a, "子目录"), file = path.join(a, "原件.txt");
  await fs.mkdir(folder, { recursive: true }); await fs.mkdir(b); await fs.writeFile(file, "original");
  const store = await new core.Store(path.join(temp, "state")).init([]); await store.addRoots([a, b]);
  const context = vm.createContext({ process, structuredClone,
    require: name => name === "electron" ? { app: { whenReady: () => ({ then() {} }), on() {}, requestSingleInstanceLock: () => true } } :
      name === "./core.cjs" ? core : name === "./documents.cjs" ? {} : name === "./update.cjs" ? { createUpdater: () => ({}) } :
      name === "../version.json" ? {} : name.startsWith("./") ? require(path.resolve(__dirname, "../src", name)) : require(name) });
  vm.runInContext(await fs.readFile(path.join(__dirname, "../src/main.cjs"), "utf8"), context);
  context.fixtureStore = store; vm.runInContext("store=fixtureStore", context);
  async function dispatch(method, args) { context.args = args; return vm.runInContext(`dispatch(${JSON.stringify(method)},args)`, context); }
  await dispatch("orderRoots", { paths: [b, a] });
  await dispatch("order", { root: a, paths: [file, folder] });
  const reopened = await new core.Store(store.stateDir).init(); await reopened.refresh();
  assert.deepEqual(reopened.settings.roots, [b, a]);
  assert.deepEqual(reopened.snapshot.rootEntries.map(e => e.path), [file, folder]);
  for (const paths of [[a], [a,a], [a,temp]]) await assert.rejects(dispatch("orderRoots", { paths }), /无效/);
  for (const paths of [[file], [file,file], [file,b]]) await assert.rejects(dispatch("order", { root:a, paths }), /无效/);
  assert.equal(await fs.readFile(file, "utf8"), "original");
});
test("archive recommendations reject screenshot false positives, generic words and numeric containers", () => {
  const names = ["招投标文件-中国烟草总公司贵州省公司-省烟草科学研究院2026年-2028年度网络信息安全运维服务采购项目", "DICT-852-202308-0001贵州茅台酒厂（集团）物流有限责任公司2023年至2024年监控运维服务合同", "202210", "7"];
  const result = rank(names.map(name => ({ name })), ["贵州省外经贸集团云资源服务租赁项目.pdf"]);
  assert(result.every(p => p.score === 0));
  assert(rank([{name:"外经贸消防项目"}], ["外经贸云资源", "消防服务项目"]).every(p => p.score === 0), "Weak per-document hits cannot accumulate");
  assert(rank([{name:"智慧工地建设项目"}], ["智慧工地建设项目技术方案.pdf"])[0].score >= 75);
  assert.equal(rank([{name:names[1]}], ["DICT-852-202308-0001验收报告.pdf"])[0].score, 100);
});
test("an in-flight refresh never restores an old selection over newer directory navigation", async () => {
  const source = await fs.readFile(path.join(__dirname, "../src/ui.cjs"), "utf8");
  const refreshSource = source.slice(source.indexOf("async function refresh()"), source.indexOf("function selectedItems()"));
  for (const pendingStage of ["refresh", "list"]) {
    let finish;
    const calls = [];
    const context = vm.createContext({ generation: 0, project: { path: "old" }, current: "old", dir: "old-dir", source: null,
      directoryRows: null, directoryPath: "", data: { snapshot: {} },
      api: method => method === pendingStage ? new Promise(resolve => { finish = resolve; }) : Promise.resolve({ snapshot: {} }),
      apply: value => calls.push("apply"), projectEntries: () => [{ path: "old" }], load: () => calls.push("load") });
    vm.runInContext(refreshSource, context);
    const pending = vm.runInContext("refresh()", context);
    await new Promise(resolve => setImmediate(resolve));
    context.generation++; context.project = { path: "new-selection" }; context.current = "new-selection"; context.dir = "new-dir";
    finish(pendingStage === "list" ? [] : { snapshot: {} });
    await pending;
    assert.equal(context.project.path, "new-selection");
    assert.equal(context.current, "new-selection");
    assert(!calls.includes("load"));
    if (pendingStage === "refresh") assert.deepEqual(calls, []);
  }
});
