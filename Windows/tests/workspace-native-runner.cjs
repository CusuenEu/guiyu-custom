"use strict";
const { app, shell, ipcMain } = require("electron");
const fs = require("node:fs/promises"), path = require("node:path"), assert = require("node:assert/strict");
const temp = process.env.GUIYU_WORKSPACE_TEST;
if (!temp || process.env.CI !== "true") throw Error("Isolated CI only");
app.setPath("temp", temp);
for (const event of ["before-quit", "will-quit", "quit"])
  app.on(event, () => console.log(`WORKSPACE ${process.arch} ${event}, pid=${process.pid}`));
const downloads = path.join(temp, "下载"), root = path.join(downloads, "关联项目库"), empty = path.join(temp, "空关联目录");
const year = path.join(root, "2026"), first = path.join(year, "甲项目"), second = path.join(year, "乙项目");
const archiveProjects = ["无纸化办公系统项目", "办公设备采购", "化工", "惠水加油站"].map(name => path.join(year, name));
const direct = path.join(downloads, "下载文件夹"), linkedSource = path.join(root, "空可归档目录");
const desktop = path.join(temp, "桌面实际位置"), desktopAlias = path.join(temp, "桌面重定向"), desktopFolder = path.join(desktop, "桌面文件夹");
const externalOpens = [];
const copiedSelections = [];
const iconSamples = [["图标演示.PPTX","powerpoint"],["网页说明.HTML","html"],["设备平面图.dwg","cad"],["技术路线.xmind","mindmap"],["现场照片.JPG","image"],["演示录像.mp4","video"],["施工进度.mpp","project"],["文档版式.ofd","ofd"],["未识别格式.zzz","unknown"]];
shell.openPath = async p => { externalOpens.push(p); return ""; };
const handle = ipcMain.handle.bind(ipcMain);
ipcMain.handle = (channel, handler) => handle(channel, (event, method, args) => {
  if (channel === "guiyu" && method === "copyFiles") copiedSelections.push(args.items.map(e => e.path));
  return handler(event, method, args);
});
async function prepare() {
  for (const dir of [first, second, empty, direct, linkedSource, desktopFolder]) await fs.mkdir(dir, { recursive: true });
  await fs.symlink(desktop, desktopAlias, "junction");
  app.setPath("desktop", desktopAlias);
  await fs.writeFile(path.join(desktopFolder, "桌面文档.txt"), "desktop");
  await fs.writeFile(path.join(first, "甲文档.txt"), "first");
  for(const [name] of iconSamples) await fs.writeFile(path.join(first,name),"isolated icon fixture");
  await fs.writeFile(path.join(root, "根目录散放文档.txt"), "root document");
  await fs.mkdir(path.join(first, "附件")); await fs.writeFile(path.join(first, "附件/内部.txt"), "nested");
  await fs.writeFile(path.join(second, "乙文档.txt"), "second");
  await fs.writeFile(path.join(direct, "下载文档.txt"), "download");
  await fs.utimes(first, new Date("2026-11-02T00:00:02Z"), new Date("2026-11-02T00:00:02Z"));
  await fs.utimes(second, new Date("2026-11-02T00:00:01Z"), new Date("2026-11-02T00:00:01Z"));
  for (const project of archiveProjects) {
    await fs.mkdir(project);
    await fs.utimes(project, new Date("2020-01-01"), new Date("2020-01-01"));
  }
  const stateDir = path.join(app.getPath("temp"), "Guiyu-windows-review");
  await fs.mkdir(stateDir, { recursive: true });
  await fs.writeFile(path.join(stateDir, "settings.json"), JSON.stringify({ roots: [root, empty],
    sources: [{ id: "downloads", name: "下载", kind: "folder", path: downloads }, { id: "linked", name: "空可归档目录", kind: "folder", path: linkedSource }, { id: "desktop", name: "桌面", kind: "folder", path: desktopAlias }], categories: [] }));
}
async function check(win) {
  const evalUI = script => win.webContents.executeJavaScript(script);
  const row = (kind, value) => `[data-${kind}=${JSON.stringify(value)}]`;
  const click = (selector, extra = {}) => evalUI(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)throw Error('Missing '+${JSON.stringify(selector)});e.dispatchEvent(new MouseEvent('click',{bubbles:true,detail:1,...${JSON.stringify(extra)}}));})()`);
  const wait = (condition, timeout = 15000) => evalUI(`new Promise((resolve,reject)=>{const until=Date.now()+${timeout};const poll=()=>{if(${condition})return resolve(true);if(Date.now()>until)return reject(Error('UI wait timed out: '+${JSON.stringify(condition)}));setTimeout(poll,20)};poll()})`);
  const content = name => `document.querySelector('#files').textContent.includes(${JSON.stringify(name)})`;
  await wait("document.querySelectorAll('[data-dir]').length>0");
  const rootFile = path.join(root, "根目录散放文档.txt");
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("rail-file",rootFile))})`), "Linked location must list its immediate files in the left rail");
  const drag = (from, to, after) => evalUI(`(()=>{
    const a=document.querySelector(${JSON.stringify(from)}),b=document.querySelector(${JSON.stringify(to)}), transfer=new DataTransfer();
    if(!a||!b)throw Error('Missing drag row');
    a.dispatchEvent(new DragEvent('dragstart',{bubbles:true,cancelable:true,dataTransfer:transfer}));
    const target=a.dataset.orderKind==='root'?b.closest('[data-root-group]'):b,rect=target.getBoundingClientRect();
    b.dispatchEvent(new DragEvent('dragover',{bubbles:true,cancelable:true,dataTransfer:transfer,clientY:rect.top+rect.height*${after?0.8:0.2}}));
    if(!target.classList.contains(${JSON.stringify(after?'insert-after':'insert-before')}))throw Error('Missing visible insertion line before drop');
    b.dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:transfer,clientY:rect.top+rect.height*${after?0.8:0.2}}));
    a.dispatchEvent(new DragEvent('dragend',{bubbles:true,dataTransfer:transfer}));
  })()`);
  await drag(row('dir',root),row('dir',empty),true);
  await wait(`document.querySelector('[data-root-group]').dataset.rootGroup===${JSON.stringify(empty)}`);
  await drag(row('rail-file',rootFile),row('dir',year),false);
  await wait(`document.querySelector(${JSON.stringify(row('root-group',root))}).querySelector('[data-order-kind="entry"]').dataset.orderPath===${JSON.stringify(rootFile)}`);
  await click('#refresh');
  await wait(`document.querySelector('[data-root-group]').dataset.rootGroup===${JSON.stringify(empty)}`);
  assert(await evalUI(`document.querySelector(${JSON.stringify(row('root-group',root))}).querySelector('[data-order-kind="entry"]').dataset.orderPath===${JSON.stringify(rootFile)}`), "Mixed file/folder order must persist after refresh");
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("dir", empty))})`), "Empty association must be visible");
  await click(row("dir", empty));
  assert(await evalUI("document.querySelector('#projects').textContent.includes('为空')"));
  await click(row("dir", year));
  await click(row("project", first)); await wait(content("甲文档.txt"));
  for(const [name,type] of iconSamples) {
    const selector=row("file",path.join(first,name))+' img[data-file-type='+JSON.stringify(type)+']';
    await wait(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});return !!e&&e.complete&&e.naturalWidth>0})()`);
  }
  console.log("PASS file icons: actual packaged HTML, PPT, CAD, mind map, image, video, Project, OFD and unknown SVG assets load in the real renderer");
  assert(await evalUI(`document.querySelector(${JSON.stringify(row("project", first))}).getAttribute('aria-selected')==='true'`));
  // Unconfigured categories must never hide an already selected folder's files.
  assert(!await evalUI("!!document.querySelector('#empty-categories')"));
  await click(row("project", second), { ctrlKey: true }); await wait(content("乙文档.txt"));
  assert.equal(await evalUI("document.querySelectorAll('#projects [aria-selected=true]').length"), 2, "Middle Ctrl multiselect");
  await evalUI("document.querySelector('#projects').focus();document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'c',ctrlKey:true,bubbles:true}))");
  await wait("document.querySelector('#toast').textContent.includes('已复制 2 项')", 45000);
  assert.deepEqual([...copiedSelections[0]].sort(), [first, second].sort(), "Middle copy must use middle folders, never right-side files");
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
  await click(row("project", root)); await wait(content("空可归档目录"));
  assert(await evalUI(content("2026")), "A linked project root inside Downloads must remain browsable as a source folder");
  await click(row("project", direct)); await wait(content("下载文档.txt"));
  await evalUI(`document.querySelector(${JSON.stringify(row("project", direct))}).dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}))`);
  await wait("document.activeElement.id==='files'");
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("project", direct))})`), "Source double-click must keep middle folder list");
  assert(await evalUI(content("下载文档.txt")));
  await evalUI(`document.querySelector(${JSON.stringify(row("project", direct))}).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:100,clientY:100}))`);
  await wait("!document.querySelector('#context').hidden&&[...document.querySelectorAll('#context button')].some(b=>b.textContent==='智能命名…')");
  await evalUI("[...document.querySelectorAll('#context button')].find(b=>b.textContent==='智能命名…').click()");
  await wait("!!document.querySelector('#name-stem')", 45000);
  await evalUI("const input=document.querySelector('#name-stem');input.value='下载新名称';input.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('#confirm-archive').click()");
  await wait("!!document.querySelector('#archive-query')", 45000);
  assert(await evalUI("document.querySelector('.file-summary').textContent.includes('下载新名称')"));
  await evalUI("document.querySelector('#modal [data-cancel]').click()");
  const renamedSource = path.join(downloads, '下载新名称');
  assert.equal(await fs.readFile(path.join(renamedSource, '下载文档.txt'), 'utf8'), 'download');
  assert(await evalUI(`document.querySelector(${JSON.stringify(row("project", renamedSource))})?.getAttribute('aria-selected')==='true'`), "Rename/archive-cancel must preserve the selected middle folder");
  await click('[data-source="linked"]');
  await wait("document.querySelector('#status').textContent==='本地工作空间'");
  assert(await evalUI("document.querySelector('#projects').textContent.includes('为空')"));
  await click('[data-source="desktop"]');
  await wait(`!!document.querySelector(${JSON.stringify(row("project", desktopFolder))})`);
  await click(row("project", desktopFolder)); await wait(content("桌面文档.txt"));
  await click(row("dir", root));
  await click(row("project", year)); await wait(content("甲项目"));
  await click(row("dir", empty));
  await fs.mkdir(path.join(empty, "新文件夹"));
  await click('#refresh'); await wait(`!!document.querySelector(${JSON.stringify(row("project", path.join(empty, "新文件夹")))})`);
  assert(await evalUI(`!!document.querySelector(${JSON.stringify(row("dir", empty))})`), "Association must remain when first child appears");
  await click(row("project", path.join(empty, "新文件夹")));
  await wait("document.querySelector('#files').textContent.includes('没有内容')");
  await checkPasteAndCategories();

  async function checkPasteAndCategories() {
    const {runPS, entry} = require(path.join(process.resourcesPath,"production.asar/src/core.cjs"));
    const {clipboard} = require("electron");
    const external = path.join(temp,"资源管理器文件 中文 $1"), document = path.join(external,"外来合同.pdf"), folder=path.join(external,"外来项目");
    await fs.mkdir(path.join(folder,"空子目录"),{recursive:true});
    await fs.writeFile(document,"original contract"); await fs.writeFile(path.join(folder,"原件.txt"),"folder original");
    const writeClipboard = paths => runPS("$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Windows.Forms;$files=New-Object System.Collections.Specialized.StringCollection;foreach($p in (ConvertFrom-Json $env:GUIYU_TEST_FILES)){[void]$files.Add($p)};$d=New-Object System.Windows.Forms.DataObject;$d.SetFileDropList($files);[Windows.Forms.Clipboard]::SetDataObject($d,$true,10,100)", {GUIYU_TEST_FILES:JSON.stringify(paths)});
    const key = async (key, selector) => {
      await evalUI(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});e.focus();e.dispatchEvent(new KeyboardEvent('keydown',{key:${JSON.stringify(key)},ctrlKey:true,bubbles:true,cancelable:true}))})()`);
    };
    const context = async selector => {
      await evalUI(`document.querySelector(${JSON.stringify(selector)}).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:200,clientY:200}))`);
      await wait("!document.querySelector('#context').hidden&&[...document.querySelectorAll('#context button')].some(b=>b.textContent==='粘贴')");
    };
    const menuClick = label => evalUI(`[...document.querySelectorAll('#context button')].find(b=>b.textContent===${JSON.stringify(label)}).click()`);
    const settled = () => wait("document.querySelector('#status').textContent==='本地工作空间'",45000);
    await writeClipboard([document,folder]);
    // A was clicked with old B still shown beforehand. Target must now be A.
    await click(row("dir",empty));
    await key("v",row("dir",empty)); await settled();
    const copiedFolder=path.join(empty,"外来项目"), copiedFile=path.join(empty,"外来合同.pdf");
    assert.equal(await fs.readFile(copiedFile,"utf8"),"original contract");
    assert.equal(await fs.readFile(path.join(copiedFolder,"原件.txt"),"utf8"),"folder original");
    assert.equal(await evalUI("document.querySelector('#projects [data-project]').dataset.project"),copiedFile);
    assert.equal(await evalUI("document.querySelectorAll('#projects [aria-selected=true]').length"),2);
    await click('#refresh'); await settled();
    assert.equal(await evalUI("document.querySelector('#projects [data-project]').dataset.project"),copiedFile);
    await key("v",'#projects'); await settled();
    assert.equal(await fs.readFile(path.join(empty,"外来合同 (2).pdf"),"utf8"),"original contract");
    assert.equal(await fs.readFile(path.join(empty,"外来项目 (2)/原件.txt"),"utf8"),"folder original");
    assert.equal(await evalUI("document.querySelectorAll('#projects [aria-selected=true]').length"),2);
    await writeClipboard([document]);
    await click(row("project",copiedFolder)); await wait(content("原件.txt"));
    await context(row("project",copiedFolder)); await menuClick("粘贴"); await settled();
    const inB=path.join(copiedFolder,"外来合同.pdf");
    assert.equal(await fs.readFile(inB,"utf8"),"original contract");
    assert.equal(await evalUI("document.querySelector('#files [data-file]').dataset.file"),inB);
    assert(await evalUI(`document.querySelector(${JSON.stringify(row('file',inB))}).getAttribute('aria-selected')==='true'`));
    const sub=path.join(copiedFolder,"空子目录");
    await evalUI(`document.querySelector(${JSON.stringify(row('file',sub))}).dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}))`);
    await wait("document.querySelector('#files').textContent.includes('没有内容')");
    await context('#files'); await menuClick("粘贴"); await settled();
    assert.equal(await fs.readFile(path.join(sub,"外来合同.pdf"),"utf8"),"original contract");
    await key("v",'#files'); await settled();
    const duplicate=path.join(sub,"外来合同 (2).pdf");
    assert.equal(await fs.readFile(duplicate,"utf8"),"original contract");
    assert.equal(await evalUI("document.querySelector('#files [data-file]').dataset.file"),duplicate);
    // Our file copy is a native CF_HDROP list, readable by Explorer's API.
    await context(row('file',duplicate)); await menuClick("复制"); await settled();
    const native=JSON.parse(await runPS("[Console]::OutputEncoding=[Text.Encoding]::UTF8;Add-Type -AssemblyName System.Windows.Forms;ConvertTo-Json -InputObject @([Windows.Forms.Clipboard]::GetFileDropList()|ForEach-Object{[string]$_}) -Compress"));
    assert.deepEqual(native,[duplicate]);
    clipboard.writeText("ordinary text"); await context('#files');
    assert(await evalUI("[...document.querySelectorAll('#context button')].find(b=>b.textContent==='粘贴').disabled"));
    await click('#settings'); await click('[data-section="文件分类"]');
    await wait("!!document.querySelector('#category-name')");
    await evalUI("document.querySelector('#category-name').focus()");
    win.webContents.sendInputEvent({type:"keyDown",keyCode:"V",modifiers:["control"]});
    win.webContents.sendInputEvent({type:"keyUp",keyCode:"V",modifiers:["control"]});
    await wait("document.querySelector('#category-name').value==='ordinary text'");
    assert.deepEqual((await fs.readdir(sub)).sort(),["外来合同 (2).pdf","外来合同.pdf"].sort());
    await evalUI("document.querySelector('#modal [data-cancel]').click()");
    // First category immediately replaces the prior source/time view; no reload.
    const note=path.join(sub,"普通说明.txt"); await fs.writeFile(note,"unmatched");
    await click('#refresh'); await settled();
    // Toolbar is hidden before the first category; retain a prior raw view state.
    await evalUI("mode='源文档';render()");
    await click('#settings'); await click('[data-section="文件分类"]');
    await evalUI("document.querySelector('#category-name').value='合同';document.querySelector('#add-category').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    await wait("document.querySelector('#category-list').textContent.includes('合同')");
    await evalUI("document.querySelector('#modal [data-cancel]').click()");
    assert(await evalUI("document.querySelector('[data-mode=\"按类别\"]').getAttribute('aria-selected')==='true'"));
    assert.deepEqual(await evalUI("[...document.querySelectorAll('#files [data-group]')].map(e=>e.textContent.replace(/\\d+$/,''))"),["合同","其他"]);
    assert.equal(await evalUI("document.querySelectorAll('#files [data-file]').length"),3);
    const settingsPath=path.join(app.getPath('temp'),'Guiyu-windows-review/settings.json');
    let saved=JSON.parse(await fs.readFile(settingsPath,"utf8"));
    assert.equal(saved.categories.length,1,"Display-only Other never changes saved categories");
    const contract=saved.categories[0];
    // Real assignment IPC remains authoritative across automatic rule changes.
    await evalUI(`api('assign',{items:[${JSON.stringify(await entry(note))}],id:${JSON.stringify(contract.id)}}).then(apply)`);
    await click('[data-mode="按时间"]');
    await click('#settings'); await click('[data-section="文件分类"]');
    await click('[data-rule]');
    await evalUI("document.querySelector('#rule-keywords').value='不存在的词';document.querySelector('#rule-extensions').value='';document.querySelector('#confirm').click()");
    await wait("!!document.querySelector('#category-list')");
    await evalUI("document.querySelector('#modal [data-cancel]').click()");
    assert(await evalUI("document.querySelector('[data-mode=\"按类别\"]').getAttribute('aria-selected')==='true'"));
    assert.equal(await evalUI("document.querySelector('#files [data-group]').textContent"),"合同1");
    assert.equal(await evalUI("document.querySelector('#files [data-file]').dataset.file"),note);
    // A real UUID Other is the sole fallback, and rule conflicts stay visible.
    saved=JSON.parse(await fs.readFile(settingsPath,"utf8"));
    const cats=[...saved.categories,{id:'uuid-other',name:'其他',rule:{...contract.rule,enabled:false}},
      {id:'tie1',name:'一',rule:contract.rule},{id:'tie2',name:'二',rule:contract.rule}];
    await evalUI(`api('categories',{categories:${JSON.stringify(cats)}}).then(apply)`);
    assert.equal(await evalUI("document.querySelector('[data-group=\"uuid-other\"]').textContent"),"其他2");
    assert.equal(await evalUI("document.querySelectorAll('#files [data-file]').length"),3);
    await writeClipboard([document]); await key('v','#files'); await settled();
    assert(await evalUI("document.querySelector('#files [data-group]').textContent==='刚复制1'"));
    await click('#refresh'); await settled();
    assert(await evalUI("document.querySelector('#files [data-group]').textContent==='刚复制1'"));
    await click('[data-mode="按类别"]');
    assert(!await evalUI("!!document.querySelector('[data-group=\"__just_copied__\"]')"));
    assert.equal(await evalUI("document.querySelectorAll('#files [data-file]').length"),4);
    await click('[data-mode="源文档"]'); await click('#up'); await settled();
    assert(await evalUI("document.querySelector('[data-mode=\"按类别\"]').getAttribute('aria-selected')==='true'"));
    await click('[data-source="downloads"]');
    await wait(`!!document.querySelector(${JSON.stringify(row('project',renamedSource))})`);
    await click(row('project',renamedSource)); await wait(content('下载文档.txt'));
    assert(await evalUI("document.querySelector('[data-mode=\"按类别\"]').getAttribute('aria-selected')==='true'"));
    assert.equal(await evalUI("document.querySelectorAll('#files [data-file]').length"),1);
    assert.equal(await fs.readFile(document,'utf8'),'original contract');
    assert.equal(await fs.readFile(path.join(folder,'原件.txt'),'utf8'),'folder original');
    console.log('PASS copy/paste: native clipboard both directions, Ctrl+V, right menus, A/B/nested empty targets, order/selection/refresh, numbered duplicates, disabled text clipboard and actual input text paste');
    console.log('PASS automatic categories: first add and rule edits reclassify immediately, default on navigation, manual assignment, UUID Other, conflicting rules, no omissions/duplicates, display-only fallback and copied-group reset');
  }
  // Exercise the actual Electron second-instance transport used by Explorer.
  // The child bypasses fixture preparation so it cannot overwrite primary state.
  const explorerFolder = path.join(temp, "右键 中文 & $1 文件夹");
  await fs.mkdir(explorerFolder);
  const originalFile = path.join(explorerFolder, "保留原件.txt");
  await fs.writeFile(originalFile, "unchanged");
  async function explorer(type, item) {
    await new Promise((resolve, reject) => {
      const child = require("node:child_process").spawn(process.execPath,
        [type, "--allow-file-access-from-files", item],
        { env: { ...process.env, GUIYU_EXPLORER_CHILD: "1" }, stdio: "ignore", windowsHide: true });
      const timer = setTimeout(() => { child.kill(); reject(Error("Explorer second instance did not exit")); }, 30000);
      child.once("error", error => { clearTimeout(timer); reject(error); });
      child.once("exit", code => { clearTimeout(timer); code === 0 ? resolve() : reject(Error(`Explorer child exit ${code}`)); });
    });
    await wait(type === "--smart-name" ? "!!document.querySelector('#name-stem')" : "!!document.querySelector('#archive-query')?.oninput", 45000);
  }
  for (const type of ["--smart-name", "--smart-archive"]) {
    await explorer(type, explorerFolder);
    assert(await evalUI("document.querySelector('#modal').textContent.includes('右键 中文 & $1 文件夹')"));
    if(type==='--smart-archive') {
      assert(await evalUI("document.querySelector('#archive-projects').textContent.includes('未找到匹配项目，可输入项目名搜索')"));
      await evalUI("document.querySelector('#archive-query').value='甲项目';document.querySelector('#archive-query').dispatchEvent(new Event('input',{bubbles:true}))");
      await wait(`!!document.querySelector(${JSON.stringify(row('target',first))})`);
      await click(row('target',first));
      assert(await evalUI("!document.querySelector('#confirm').disabled"));
      await evalUI("document.querySelector('#archive-query').value='';document.querySelector('#archive-query').dispatchEvent(new Event('input',{bubbles:true}))");
      assert(await evalUI("document.querySelector('#confirm').disabled&&document.querySelector('#archive-projects').textContent.includes('未找到匹配项目，可输入项目名搜索')"));
    }
    await evalUI("document.querySelector('#modal [data-cancel]').click()");
    await wait("!document.querySelector('#modal').open");
    assert.equal(await fs.readFile(originalFile, "utf8"), "unchanged");
  }
  const matched = path.join(explorerFolder, "法律意见书暨仲裁预案-无纸化办公.docx");
  await fs.writeFile(matched, "filename-only fixture");
  await explorer("--smart-archive", matched);
  const choices = await evalUI(`[...document.querySelectorAll('#archive-projects [data-target]')].map(button => ({
    path: button.dataset.target, marks: [...button.querySelectorAll('mark')].map(mark => mark.textContent)
  }))`);
  assert.deepEqual(choices, [
    { path: archiveProjects[0], marks: ["无纸化办公"] },
    { path: archiveProjects[1], marks: ["办公"] },
  ]);
  const selectedChoice = row("target", archiveProjects[0]);
  const markStyle = selector => evalUI(`(()=>{const mark = document.querySelector(${JSON.stringify(selector + " mark")}); const style = getComputedStyle(mark); return [style.backgroundColor,style.color];})()`);
  const expectedMark = ["rgb(249, 218, 221)", "rgb(49, 27, 29)"];
  assert.deepEqual(await markStyle(selectedChoice), expectedMark);
  await click(selectedChoice);
  assert.deepEqual(await markStyle(selectedChoice), expectedMark, "Selecting a project must preserve its matching highlight");
  assert.equal(await fs.readFile(matched, "utf8"), "filename-only fixture");
  assert.deepEqual(await fs.readdir(archiveProjects[0]), []);
  await click('#modal [data-cancel]');

  const unmatched = path.join(explorerFolder, "待办.txt");
  await fs.writeFile(unmatched, "惠水加油站");
  await explorer("--smart-archive", unmatched);
  assert.equal(await evalUI("document.querySelector('#archive-projects').textContent"), "未找到匹配项目，可输入项目名搜索");
  await evalUI("document.querySelector('#archive-query').value='惠水';document.querySelector('#archive-query').dispatchEvent(new Event('input',{bubbles:true}))");
  assert.equal(await evalUI("document.querySelector('#archive-projects h3').textContent"), "搜索结果");
  assert.equal(await evalUI("document.querySelectorAll('#archive-projects mark').length"), 0);
  await click(row("target", archiveProjects[3]));
  assert.equal(await fs.readFile(unmatched, "utf8"), "惠水加油站");
  assert.deepEqual(await fs.readdir(archiveProjects[3]), []);
  await click('#confirm');
  await wait("!document.querySelector('#modal').open");
  await assert.rejects(fs.stat(unmatched), { code: "ENOENT" });
  assert.equal(await fs.readFile(path.join(archiveProjects[3], "待办.txt"), "utf8"), "惠水加油站");
  console.log("PASS archive: filename-only ranking, selected highlight, independent empty/search lists, and actual move after confirmation");
  assert.deepEqual(externalOpens, [], "Folder interactions must never launch Explorer");
  console.log("PASS renderer: selection, Ctrl multiselect, middle Ctrl+C IPC/clipboard, keyboard, category-free contents, nested browse, overlapping sources, redirected Desktop, rename/archive-cancel selection, empty association and refresh");
  console.log("PASS Explorer: real second-instance smart naming/archive with Chromium switches and Chinese/space/special-character paths");
  console.log("PASS rail/archive: immediate files, root and mixed child order, insertion lines before release, persisted refresh, empty recommendations and independent manual search");
}
let tested = false;
app.on("browser-window-created", (event, win) => {
  if (tested) return; tested = true;
  win.webContents.once("did-finish-load", () => check(win).then(async () => {
    await win.webContents.executeJavaScript("apiQueue.then(() => true)");
    console.log(`WORKSPACE ${process.arch} all assertions complete; requesting normal application quit`);
    // Leave the executeJavaScript completion callback before closing Chromium.
    // A stuck shutdown still fails the parent timeout; it is never a success.
    setImmediate(() => app.quit());
  }).catch(async error => {
    console.error(error.stack || error);
    try { console.error(await win.webContents.executeJavaScript("document.body.innerText")); } catch {}
    setImmediate(() => app.exit(1));
  }));
});
if (process.env.GUIYU_EXPLORER_CHILD === "1") require(path.join(process.resourcesPath, "production.asar/src/main.cjs"));
else prepare().then(() => require(path.join(process.resourcesPath, "production.asar/src/main.cjs"))).catch(error => { console.error(error); app.exit(1); });
