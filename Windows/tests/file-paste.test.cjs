"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs/promises"), os = require("node:os"), path = require("node:path");
const { pasteFiles } = require("../src/file-paste.cjs");
const { category, fallbackID, pasteTarget } = require("../src/workspace-model.js");
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-paste-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const source = path.join(root, "来源"), dest = path.join(root, "目标");
  await fs.mkdir(source); await fs.mkdir(dest);
  return { root, source, dest };
}
test("recursive copy preserves originals and hidden descendants, keeps selection order and numbers duplicates", async t => {
  const { source, dest } = await fixture(t);
  const folder = path.join(source, "项目"), document = path.join(source, "合同.pdf");
  await fs.mkdir(path.join(folder, "子目录"), { recursive: true });
  await fs.writeFile(path.join(folder, "子目录/.内部"), "all contents");
  await fs.writeFile(document, "contract");
  for (const suffix of ["", " (2)", " (3)"]) {
    const result = await pasteFiles([folder, path.join(folder, "子目录/.内部"), document], dest);
    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.copied.map(e => e.name), [`项目${suffix}`, `合同${suffix}.pdf`]);
    assert.equal(await fs.readFile(path.join(dest, `项目${suffix}/子目录/.内部`), "utf8"), "all contents");
    assert.equal(await fs.readFile(path.join(dest, `合同${suffix}.pdf`), "utf8"), "contract");
  }
  assert.equal(await fs.readFile(document, "utf8"), "contract");
});
test("reject self and descendant copies, while ordinary same-directory file copies get a safe name", async t => {
  const { source } = await fixture(t);
  const sub = path.join(source, "子目录"); await fs.mkdir(sub);
  for (const target of [source, sub]) {
    const result = await pasteFiles([source], target);
    assert.equal(result.copied.length, 0); assert.match(result.errors[0].message, /自身/);
  }
  const file = path.join(source, "合同.pdf"); await fs.writeFile(file, "unchanged");
  assert.equal((await pasteFiles([file], source)).copied[0].name, "合同 (2).pdf");
});
test("partial failure rolls back unfinished tree, reports completed items and leaves preexisting files intact", async t => {
  const { source, dest } = await fixture(t);
  const folder = path.join(source, "坏目录"), file = path.join(source, "好.txt");
  await fs.mkdir(folder); await fs.writeFile(path.join(folder, "a.txt"), "one");
  await fs.writeFile(path.join(folder, "b.txt"), "two"); await fs.writeFile(file, "good");
  await fs.writeFile(path.join(dest, "好.txt"), "existing");
  const io = { ...fs, copyFile: async (from, to, flags) => {
    if (path.basename(from) === "b.txt") throw Error("磁盘空间不足");
    return fs.copyFile(from, to, flags);
  } };
  const result = await pasteFiles([folder, file, path.join(source, "missing")], dest, { io });
  assert.deepEqual(result.copied.map(e => e.name), ["好 (2).txt"]);
  assert.equal(result.errors.length, 2);
  assert.deepEqual((await fs.readdir(dest)).sort(), ["好 (2).txt", "好.txt"].sort());
  assert.equal(await fs.readFile(path.join(dest, "好.txt"), "utf8"), "existing");
  assert.equal(await fs.readFile(path.join(folder, "b.txt"), "utf8"), "two");
});
test("simultaneous copies cannot overwrite a previously reserved destination", async t => {
  const { source, dest } = await fixture(t), file = path.join(source, "文档.txt");
  await fs.writeFile(file, "contents");
  const results = await Promise.all([pasteFiles([file], dest), pasteFiles([file], dest)]);
  assert(results.every(r => !r.errors.length));
  assert.deepEqual((await fs.readdir(dest)).sort(), ["文档 (2).txt", "文档.txt"].sort());
});
test("three-pane targets ignore stale right contents and handle nested/empty/source folders", () => {
  const state = { pane: "directories", dir: "A", current: "stale", active: {path:"stale"}, selected: new Set(), middleRows: [] };
  assert.equal(pasteTarget(state), "A");
  state.pane = "projects"; assert.equal(pasteTarget(state), "A");
  state.middleRows = [{path:"B",folder:true}]; state.selected.add("B");
  assert.equal(pasteTarget(state), "B");
  state.middleRows.push({path:"Z",folder:true}); state.selected.add("Z"); state.active={path:"B",folder:true};
  assert.equal(pasteTarget(state), "B");
  state.pane = "files"; state.current = "B/C"; assert.equal(pasteTarget(state), "B/C");
  state.source = {kind:"folder",path:"Downloads"}; state.sourcePreviewCurrent="Downloads/B/empty";
  assert.equal(pasteTarget(state), "Downloads/B/empty");
  state.pane="projects"; state.selected.clear(); state.current="Downloads";
  assert.equal(pasteTarget(state), "Downloads");
  state.source={kind:"recent"}; assert.equal(pasteTarget(state), "");
});
const rule = keywords => ({enabled:true, scope:"文件和文件夹",keywords,excludedKeywords:[],extensions:[],priority:0});
test("classification preserves manual identity, handles conflicts and UUID Other without modifying settings", () => {
  const item={path:"/file", name:"合同.pdf", identity:"1"};
  const settings={categories:[{id:"contract",name:"合同",rule:rule(["合同"])}], assignments:{}};
  assert.equal(category(item,settings),"contract");
  assert.equal(category({...item,name:"说明.txt"},settings),fallbackID);
  settings.categories.push({id:"duplicate",name:"业务",rule:rule(["合同"])});
  assert.equal(category(item,settings),fallbackID);
  settings.categories.push({id:"uuid-other",name:"其他",rule:rule(["合同"])});
  assert.equal(category(item,settings),"uuid-other");
  settings.assignments[item.path]={identity:"1",categoryID:"duplicate"};
  assert.equal(category(item,settings),"duplicate");
  assert.equal(category({...item,identity:"replaced"},settings),"uuid-other");
  assert.equal(settings.categories.length,3);
});
