"use strict";
const { app, BrowserWindow, shell } = require("electron");
const fs = require("node:fs/promises"), path = require("node:path"), assert = require("node:assert/strict");
const temp = process.env.GUIYU_WORKSPACE_TEST;
if (!temp || process.env.CI !== "true") throw Error("Isolated CI only");
const downloads = path.join(temp, "下载"), root = path.join(downloads, "关联项目库"), empty = path.join(temp, "空关联目录");
const year = path.join(root, "2026"), first = path.join(year, "甲项目"), second = path.join(year, "乙项目");
const direct = path.join(downloads, "下载文件夹"), linkedSource = path.join(root, "空可归档目录");
const externalOpens = [];
shell.openPath = async p => { externalOpens.push(p); return ""; };
async function prepare() {
  for (const dir of [first, second, empty, direct, linkedSource]) await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(first, "甲文档.txt"), "first");
  await fs.mkdir(path.join(first, "附件")); await fs.writeFile(path.join(first, "附件/内部.txt"), "nested");
  await fs.writeFile(path.join(second, "乙文档.txt"), "second");
  await fs.writeFile(path.join(direct, "下载文档.txt"), "download");
  await fs.utimes(first, new Date("2026-11-02T00:00:02Z"), new Date("2026-11-02T00:00:02Z"));
  await fs.utimes(second, new Date("2026-11-02T00:00:01Z"), new Date("2026-11-02T00:00:01Z"));
  const stateDir = path.join(app.getPath("temp"), "Guiyu-windows-review");
  await fs.mkdir(stateDir, { recursive: true });
  await fs.writeFile(path.join(stateDir, "settings.json"), JSON.stringify({ roots: [root, empty],
    sources: [{ id: "downloads", name: "下载", kind: "folder", path: downloads }, { id: "linked", name: "空可归档目录", kind: "folder", path: linkedSource }], categories: [] }));
}
async function check(win) {
  const evalUI = script => win.webContents.executeJavaScript(script);
  const row = (kind, value) => `[data-${kind}=${JSON.stringify(value)}]`;
  const click = (selector, extra = {}) => evalUI(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)throw Error('Missing '+${JSON.stringify(selector)});e.dispatchEvent(new MouseEvent('click',{bubbles:true,detail:1,...${JSON.stringify(extra)}}));})()`);
  const wait = (condition) => evalUI(`new Promise((resolve,reject)=>{const until=Date.now()+15000;const poll=()=>{if(${condition})return resolve(true);if(Date.now()>until)return reject(Error('UI wait timed out: '+${JSON.stringify(condition)}));setTimeout(poll,20)};poll()})`);
  const content = name => `document.querySelector('#files').textContent.includes(${JSON.stringify(name)})`;
  await wait("document.querySelectorAll('[data-dir]').length>0");
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("dir", empty))})`), "Empty association must be visible");
  await click(row("dir", empty));
  assert(await evalUI("document.querySelector('#projects').textContent.includes('为空')"));
  await click(row("dir", year));
  await click(row("project", first)); await wait(content("甲文档.txt"));
  assert(await evalUI(`document.querySelector(${JSON.stringify(row("project", first))}).getAttribute('aria-selected')==='true'`));
  // Unconfigured categories must never hide an already selected folder's files.
  assert(!await evalUI("!!document.querySelector('#empty-categories')"));
  await click(row("project", second), { ctrlKey: true }); await wait(content("乙文档.txt"));
  assert.equal(await evalUI("document.querySelectorAll('#projects [aria-selected=true]').length"), 2, "Middle Ctrl multiselect");
  await click(row("project", first)); await wait(content("甲文档.txt"));
  await evalUI(`document.querySelector(${JSON.stringify(row("project", first))}).dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}))`);
  await wait("document.activeElement.id==='files'"); assert(await evalUI(content("甲文档.txt")));
  await click(row("file", path.join(first, "附件")));
  await evalUI(`document.querySelector(${JSON.stringify(row("file", path.join(first, "附件")))}).dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}))`);
  await wait(content("内部.txt"));
  await click('#up'); await wait(content("甲文档.txt"));
  await click(row("dir", year));
  await click(row("project", first)); await wait(content("甲文档.txt"));
  await evalUI("document.querySelector('#projects').focus();document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}))");
  await wait(content("乙文档.txt"));
  await click('[data-source="downloads"]');
  await wait(`!!document.querySelector(${JSON.stringify(row("project", direct))})`);
  await click(row("project", direct)); await wait(content("下载文档.txt"));
  await evalUI(`document.querySelector(${JSON.stringify(row("project", direct))}).dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}))`);
  await wait("document.activeElement.id==='files'");
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("project", direct))})`), "Source double-click must keep middle folder list");
  assert(await evalUI(content("下载文档.txt")));
  await click('[data-source="linked"]');
  await wait("document.querySelector('#status').textContent==='本地工作空间'");
  assert(await evalUI("document.querySelector('#projects').textContent.includes('为空')"));
  await click(row("dir", root));
  await click(row("project", year)); await wait(content("甲项目"));
  await click(row("dir", empty));
  await fs.mkdir(path.join(empty, "新文件夹"));
  await click('#refresh'); await wait(`!!document.querySelector(${JSON.stringify(row("project", path.join(empty, "新文件夹")))})`);
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("dir", empty))})`), "Association must remain when first child appears");
  await click(row("project", path.join(empty, "新文件夹")));
  await wait("document.querySelector('#files').textContent.includes('没有内容')");
  assert.deepEqual(externalOpens, [], "Folder interactions must never launch Explorer");
  console.log("PASS renderer: selection, Ctrl multiselect, keyboard, category-free contents, nested browse, sources, empty association and refresh");
}
let tested = false;
app.on("browser-window-created", (event, win) => {
  if (tested) return; tested = true;
  win.webContents.once("did-finish-load", () => check(win).then(() => app.exit(0)).catch(async error => {
    console.error(error.stack || error);
    try { console.error(await win.webContents.executeJavaScript("document.body.innerText")); } catch {}
    app.exit(1);
  }));
});
prepare().then(() => require(path.join(process.resourcesPath, "production.asar/src/main.cjs"))).catch(error => { console.error(error); app.exit(1); });
