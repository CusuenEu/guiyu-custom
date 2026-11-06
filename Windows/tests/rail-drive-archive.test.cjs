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
test("archive recommendations use consecutive name characters and highlight original text", () => {
  const projects = ["化工", "办公设备采购", "无纸化办公系统项目"].map(name => ({ name }));
  const matches = rank(projects, [{ name: "法律意见书暨仲裁预案-无纸化办公.docx" }]);
  assert.deepEqual(matches.map(p => [p.name, p.longest, p.total]), [
    ["无纸化办公系统项目", 5, 5],
    ["办公设备采购", 2, 2],
  ]);
  assert.deepEqual(matches.map(p => p.matchingRanges.map(([a, b]) => p.name.slice(a, b))), [["无纸化办公"], ["办公"]]);
  const [unicode] = rank([{ name: "🪴Ａe\u0301甲" }], [{ name: "aé甲.txt" }]);
  assert.deepEqual(unicode.matchingRanges, [[2, 6]]);
  assert.equal(unicode.longest, 3);
});

test("archive ranking prefers the longest run, then unique covered characters summed per item", () => {
  const projects = ["甲乙丙、丁戊己、庚辛", "甲乙丙丁"].map(name => ({ name }));
  const matches = rank(projects, [{ name: "甲乙丙丁戊己庚辛" }]);
  assert.deepEqual(matches.map(p => [p.longest, p.total]), [[4, 4], [3, 8]]);
  const batch = rank(["甲乙丙、庚辛", "甲乙丙", "己庚"].map(name => ({ name })),
    [{ name: "甲乙丙.docx" }, { name: "庚辛.pdf" }, { name: "己" }]);
  assert.deepEqual(batch.map(p => [p.name, p.longest, p.total]), [
    ["甲乙丙、庚辛", 3, 5], ["甲乙丙", 3, 3],
  ]);
  assert.equal(rank([{ name: "甲乙、甲乙" }], [{ name: "甲乙" }])[0].total, 2);
});

test("archive runs stop at spaces and punctuation and strip only file extensions", () => {
  const names = ["乙甲", "甲-乙", "甲 乙", "docx"].map(name => ({ name }));
  assert.deepEqual(rank(names, [{ name: "甲乙" }, { name: "报告.docx" }]), []);
  assert.deepEqual(rank([{ name: "甲乙" }], [{ name: "甲-乙" }, { name: "甲 乙" }]), []);
  assert.equal(rank([{ name: "docx资料" }], [{ name: "报告.docx", folder: true }])[0].longest, 4);
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
