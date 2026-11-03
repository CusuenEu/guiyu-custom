"use strict";
const $ = (s) => document.querySelector(s),
  $$ = (s) => [...document.querySelectorAll(s)];
const esc = (s) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const norm = (s) =>
  String(s).normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
const match = (s, q) =>
  norm(q)
    .trim()
    .split(/\s+/)
    .every((t) => norm(s).includes(t));
const basename = (p) => p.split(/[\\/]/).filter(Boolean).at(-1) || p;
const folder = '<span class="folder-icon" aria-hidden="true"></span>';
const icon = (e) => {
  const type = GuiyuFileIcons.identify(e.name || e.path, { isDirectory: Boolean(e.folder) });
  return type
    ? `<img aria-hidden="true" alt="" class="file-type-icon" data-file-type="${type.id}" src="../assets/file-icons/${type.id}.svg" width="28" height="28" draggable="false">`
    : folder;
};

let data,
  dir = "",
  project = null,
  source = null,
  sourceFolder = null,
  sourcePreviewCurrent = "",
  sourceChildren = [],
  previewLoading = false,
  selectionPane = "projects",
  sourceGeneration = 0,
  previewLoad = Promise.resolve(),
  current = "",
  rows = [],
  query = "",
  mode = "按类别",
  sort = "月份倒序",
  selected = new Set(),
  anchor = null,
  collapsed = new Set(),
  generation = 0,
  section = "文件位置",
  dragItems = [],
  dragDir = null,
  working = false;
let apiQueue = Promise.resolve();
let directoryRows = null, directoryPath = "", railFile = "";
let operationPane = "projects";
const recentCopies = new Map();
function resetClassification() {
  mode = "按类别"; collapsed.clear(); recentCopies.clear();
}
function rightLocation() { return source ? sourcePreviewCurrent : current; }
function copyRank(location, p) {
  const i = (recentCopies.get(location) || []).indexOf(p);
  return i < 0 ? Infinity : i;
}
function pasteTarget() {
  if (query) return "";
  if (operationPane === "files" && (folderError || folderLoading || previewLoading)) return "";
  if (!source && data.snapshot.unavailable.includes(dir)) return "";
  return GuiyuWorkspace.pasteTarget({ pane: operationPane, source, dir, current,
    sourcePreviewCurrent, active: activeFolder(), selected, middleRows });
}
function copySelection(items = selectedItems()) {
  if (!items.length) return;
  return action(async () => {
    const result = await api("copyFiles", { items });
    toast(`已复制 ${result.count} 项，可在归屿或资源管理器粘贴`);
  });
}
function pasteSelection(destination = pasteTarget()) {
  if (!destination) return;
  return action(async () => {
    const result = await api("pasteFiles", { destination });
    const paths = result.copied.map(e => e.path);
    recentCopies.set(destination, [...paths, ...(recentCopies.get(destination) || []).filter(p => !paths.includes(p))]);
    await refresh();
    if (paths.length) {
      const right = rightLocation() === destination && activeFolder();
      const middle = (source ? current || source.path : dir) === destination;
      if (right || middle) {
        focusPane(right ? "files" : "projects");
        selected = new Set(paths); anchor = null; render();
        $(selectionPane === "files" ? "#files" : "#projects").focus({ preventScroll: true });
        $(selectionPane === "files" ? "#files" : "#projects").scrollTop = 0;
      }
    }
    toast(result.errors.length
      ? `已完成 ${paths.length} 项，${result.errors.length} 项失败：${result.errors.map(e => basename(e.path) + "：" + e.message).join("；")}`
      : `已粘贴 ${paths.length} 项`, result.errors.length > 0);
  });
}
async function clipboardActions(items = []) {
  const target = pasteTarget();
  let count = 0;
  try { count = (await api("clipboardFiles", { destination: target })).count; } catch {}
  return [
    { label: "复制", disabled: !items.length || working, fn: () => copySelection(items) },
    { label: "粘贴", disabled: !target || !count || working, fn: () => pasteSelection(target) },
    null,
  ];
}
const api = (method, arg) => {
  if (!window.guiyu) throw Error("请从归屿应用启动。");
  const request = apiQueue.then(() => window.guiyu.invoke(method, arg));
  apiQueue = request.catch(() => {});
  return request;
};
let toastTimer;
function toast(text, error = false) {
  $("#toast").textContent = text;
  $("#toast").className = error ? "error" : "";
  $("#toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(
    () => ($("#toast").hidden = true),
    error ? 10000 : 4000,
  );
}
async function action(fn) {
  if (working) return;
  working = true;
  $("#status").textContent = "正在处理…";
  try {
    return await fn();
  } catch (e) {
    toast(e.message, true);
  } finally {
    working = false;
    $("#status").textContent = "本地工作空间";
  }
}
function apply(d) {
  if (data && JSON.stringify(data.settings.categories) !== JSON.stringify(d.settings.categories)) resetClassification();
  data = d;
  const w = data.settings.widths || [240, 390];
  document.documentElement.style.setProperty("--left", w[0] + "px");
  document.documentElement.style.setProperty("--middle", w[1] + "px");
  $("#directory-section").style.height =
    data.settings.sidebarFraction * 100 + "%";
  if (!data.settings.roots.includes(dir) && !data.snapshot.directories.some((d) => d.path === dir)) {
    dir = data.settings.roots[0] || data.snapshot.directories[0]?.path || "";
    project = null;
    if (!source) current = "";
  }
  if (project && !projectEntries().some((p) => p.path === project.path)) {
    project = null;
    current = "";
  }
  if (source) source = data.settings.sources.find(s => s.id === source.id) || null;
  rail();
  render();
}
function rail() {
  const roots = data.settings.roots;
  $("#directories").innerHTML =
    roots
      .map(
        (root) =>
          `<section class="root-group" data-root-group="${esc(root)}"><button data-dir="${esc(root)}" data-order-path="${esc(root)}" data-order-root="${esc(root)}" data-order-kind="root" draggable="true" class="root-entry ${!source && dir === root && !railFile ? "active" : ""}" title="${esc(root)} · 拖动调整关联位置顺序">${folder}<span>${esc(basename(root) || root)}</span></button><div class="rail-children">` +
          (data.snapshot.rootEntries || [])
            .filter((d) => d.directory === root)
            .map(
              (d) =>
                `<button ${d.folder ? `data-dir="${esc(d.path)}"` : `data-rail-file="${esc(d.path)}"`} data-order-path="${esc(d.path)}" data-order-root="${esc(root)}" data-order-kind="entry" draggable="true" class="nested-dir ${!source && (dir === d.path || railFile === d.path) ? "active" : ""}" title="${esc(d.path)} · 拖动调整顺序">${icon(d)}<span>${esc(d.name)}</span></button>`,
            )
            .join("") + (data.snapshot.unavailable.includes(root) ? '<p class="root-label">暂时无法读取，请检查磁盘或权限</p>' : !(data.snapshot.rootEntries || []).some(e => e.directory === root) ? '<p class="root-label">此关联位置为空</p>' : '') + '</div></section>',
      )
      .join("") || '<div class="root-label">关联项目总目录开始使用</div>';
  $("#sources").innerHTML = data.settings.sources
    .map(
      (s) =>
        `<button data-source="${esc(s.id)}" class="${source?.id === s.id ? "active" : ""}" title="${esc(s.path || "关联文件夹")}"><span aria-hidden="true" style="font-size:23px">${s.id === "desktop" ? "▣" : "⇩"}</span><span>${esc(s.name)}</span></button>`,
    )
    .join("");
}
function order(a, b) {
  return sort === "最近修改"
    ? b.mtime - a.mtime
    : Number(b.name.match(/^(1[0-2]|[1-9])月/)?.[1] || 0) -
        Number(a.name.match(/^(1[0-2]|[1-9])月/)?.[1] || 0) ||
        b.mtime - a.mtime ||
        a.name.localeCompare(b.name, "zh");
}
function relevance(e) {
  const n = norm(e.name),
    q = norm(query);
  return n === q ? 0 : n.startsWith(q) ? 1 : 2;
}
let visibleRows = [], middleRows = [], fileRows = [];
let folderLoading = false, folderError = "";
function projectEntries(snapshot = data.snapshot) {
  if (directoryPath === dir && directoryRows && snapshot === data.snapshot) return directoryRows;
  return [...(snapshot.rootEntries || []), ...snapshot.projects].filter(p => p.directory === dir);
}
function fileIndex() { return [...data.snapshot.files, ...(data.snapshot.rootFiles || [])]; }
function activeFolder() { return source ? sourceFolder : project; }
function middleSelected(e) { return selectionPane === "projects" ? selected.has(e.path) : activeFolder()?.path === e.path; }
function focusPane(pane) {
  operationPane = pane;
  if (selectionPane !== pane) {
    selected.clear(); anchor = null;
    const context = activeFolder();
    if (pane === "projects" && context && middleRows.some(e => e.path === context.path)) {
      selected.add(context.path); anchor = middleRows.findIndex(e => e.path === context.path);
    }
  }
  selectionPane = pane;
  visibleRows = pane === "projects" ? middleRows : fileRows;
}

function render() {
  if (!data) return;
  let projects = source
    ? rows
    : projectEntries();
  if (query)
    projects = projects.filter(
      (p) =>
        match(p.name, query) ||
        (!source &&
          fileIndex().some(
            (e) => e.project === p.path && match(e.name, query),
          )),
    );
  projects = [...projects].sort(
    (a, b) => copyRank(source ? current || source.path : dir, a.path) - copyRank(source ? current || source.path : dir, b.path) || (query ? relevance(a) - relevance(b) : 0) || (source ? b.mtime-a.mtime || a.name.localeCompare(b.name,'zh') : order(a, b)),
  );
  middleRows = projects;
  const projectMarkup =
    projects
      .map(
        (e) =>
          `<div role="option" tabindex="-1" aria-selected="${middleSelected(e)}" class="project-row ${source ? "source-row" : ""} ${middleSelected(e) ? "selected" : ""}" data-project="${esc(e.path)}" title="${esc(e.name)}">${icon(e)}<span class="name">${esc(e.name)}</span>${source ? `<span class="date">${esc(new Intl.DateTimeFormat("sv-SE",{year:"numeric",month:"2-digit",day:"2-digit"}).format(e.mtime))}</span>` : ""}</div>`,
      )
      .join("") ||
    `<div class="empty">${folder}<span>${!data.settings.roots.length && !source ? "在设置中选择项目总目录，开始浏览" : data.snapshot.unavailable.includes(dir) && !source ? "当前关联目录无法读取，请检查路径或访问权限" : "当前目录为空，没有匹配的项目或文件"}</span>${!data.settings.roots.length && !source ? '<button id="empty-settings">打开设置</button><button id="demo">体验示例空间</button>' : ""}</div>`;
  const existingProjects = [...$("#projects").querySelectorAll("[data-project]")];
  if (projects.length && existingProjects.length === projects.length && existingProjects.every((el, i) => el.dataset.project === projects[i].path && el.title === projects[i].name)) {
    existingProjects.forEach((el, i) => {
      const active = middleSelected(projects[i]);
      el.classList.toggle("selected", active);
      el.setAttribute("aria-selected", String(active));
    });
  } else $("#projects").innerHTML = projectMarkup;
  $("#subnav").innerHTML = "";
  $("#source-subnav").innerHTML = "";
  if(source?.kind==='folder' && current && current!==source.path) renderBreadcrumbs(source.path,'#source-subnav',source.name);
  $(".file-toolbar").hidden = Boolean((!activeFolder() && !query) || !data.settings.categories.length);
  let files = [];
  if (source && sourceFolder) {
    files = [...sourceChildren].sort((a, b) => Number(b.folder) - Number(a.folder) || a.name.localeCompare(b.name, "zh"));
    sourceChildren = files;
    renderBreadcrumbs(sourceFolder.path, "#subnav", sourceFolder.name, sourcePreviewCurrent);
  } else if (query && !source) {
    files = fileIndex().filter(
      (e) => e.directory === dir && match(e.name, query),
    );
    $("#subnav").textContent =
      "搜索结果 · 全部项目" +
      (data.snapshot.unavailable.length ? " · 部分目录无法读取" : "");
  } else if (project && !source) {
    files = rows;
    renderBreadcrumbs(project.path);
  }
  fileRows = files;
  visibleRows = selectionPane === "projects" ? middleRows : fileRows;
  const available = new Set(visibleRows.map(e => e.path));
  for (const p of selected) if (!available.has(p)) selected.delete(p);
  let body = "";
  if (folderError && activeFolder()) body = `<div class="empty">无法读取当前文件夹：${esc(folderError)}</div>`;
  else if (!source && project && folderLoading) body = '<div class="empty">正在读取文件夹…</div>';
  else if (source && sourceFolder && previewLoading) body = '<div class="empty">正在读取文件夹…</div>';
  else if (!data.settings.categories.length && !activeFolder() && !query)
    body =
      '<div class="empty"><button id="empty-categories">请设置文件分类</button></div>';
  else if (!activeFolder() && !query) body = "";
  else if (!files.length)
    body =
      '<div class="empty">' +
      (query ? "没有匹配的文件或文件夹" : "当前文件夹没有内容") +
      "</div>";
  else if (mode === "源文档" || !data.settings.categories.length) {
    body = [...files]
      .sort(
        (a, b) =>
          copyRank(rightLocation(), a.path) - copyRank(rightLocation(), b.path) ||
          Number(b.folder) - Number(a.folder) ||
          a.name.localeCompare(b.name, "zh"),
      )
      .map(fileRow)
      .join("");
  } else {
    const fresh = files.filter(e => Number.isFinite(copyRank(rightLocation(), e.path)))
      .sort((a,b) => copyRank(rightLocation(), a.path) - copyRank(rightLocation(), b.path));
    if (fresh.length) body += groupHeader("__just_copied__", "刚复制", fresh.length) + fresh.map(fileRow).join("");
    const remaining = files.filter(e => !fresh.includes(e));
    let groups = new Map();
    if (mode === "按类别") {
      for (const c of data.settings.categories)
        groups.set(c.id, { name: c.name, items: [] });
      groups.set(GuiyuWorkspace.fallbackID, { name: "其他", items: [] });
      for (const e of remaining) {
        let c = category(e);
        if (groups.has(c)) groups.get(c).items.push(e);
      }
      for (const [id, g] of groups)
        if (g.items.length)
          body +=
            groupHeader(id, g.name, g.items.length) +
            (collapsed.has(id) ? "" : g.items.map(fileRow).join(""));
    } else {
      for (const e of [...remaining].sort((a, b) => b.mtime - a.mtime)) {
        const k = new Intl.DateTimeFormat("zh-CN", {
          year: "numeric",
          month: "long",
        }).format(e.mtime);
        if (!groups.has(k)) groups.set(k, { items: [] });
        groups.get(k).items.push(e);
      }
      for (const [id, g] of groups)
        body +=
          groupHeader(id, id, g.items.length) +
          (collapsed.has(id) ? "" : g.items.map(fileRow).join(""));
    }
  }
  $("#files").innerHTML = body;
  const byPath = new Map(files.map(e => [e.path, e]));
  fileRows = [...$("#files").querySelectorAll("[data-file]")].map(el => byPath.get(el.dataset.file)).filter(Boolean);
  visibleRows = selectionPane === "projects" ? middleRows : fileRows;
  $("#count").textContent =
    (source && sourceFolder) || (!source && (project || query)) ? `${files.length} 个项目` : "";
  $("#selected-count").textContent = `已选 ${selected.size} 项`;
  $("#batch-tools").hidden = selectionPane === "projects" || selected.size < 2;
  $$("[data-mode]").forEach((b) =>
    b.setAttribute("aria-selected", b.dataset.mode === mode),
  );
}
function category(e) { return GuiyuWorkspace.category(e, data.settings); }
function groupHeader(id, name, count) {
  return `<div role="button" tabindex="0" aria-expanded="${!collapsed.has(id)}" class="category-header" data-group="${esc(id)}"><svg class="chevron" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true" style="transform:rotate(${collapsed.has(id)?'-90deg':'0deg'})"><path d="m2 4 4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg><span>${esc(name)}</span><small>${count}</small></div>`;
}
function fileRow(e) {
  return `<div role="option" aria-selected="${selected.has(e.path)}" class="file-row ${selected.has(e.path) ? "selected" : ""}" data-file="${esc(e.path)}" draggable="true" title="${esc(e.name)}">${icon(e)}<div class="name-wrap"><div class="name">${esc(e.name)}</div>${query ? `<small>${esc(e.projectName)}</small>` : ""}</div><span class="date">${esc(new Intl.DateTimeFormat("sv-SE", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(e.mtime))}</span></div>`;
}
async function load() {
  const gen = ++generation;
  let next = [];
  if (source) next = source.kind==='folder' && current && current!==source.path ? await api("list",{path:current}) : await api("source", { id: source.id });
  else if (current) next = await api("list", { path: current });
  if (gen !== generation) return;
  rows = next;
  if (source && sourceFolder) {
    try {
      if (source.kind === "recent" && sourcePreviewCurrent !== sourceFolder.path)
        await api("list", { path: sourceFolder.path });
      sourceChildren = await api("list", { path: sourcePreviewCurrent });
    }
    catch (e) { sourceFolder = null; sourcePreviewCurrent = ""; sourceChildren = []; toast(e.message, true); }
  }
  if (gen !== generation) return;
  folderLoading = false; previewLoading = false; folderError = "";
  if (selectionPane === "files") selected.clear();
  render();
}
async function refresh() {
  const gen = ++generation;
  let p = project?.path,
    c = current;
  const d = await api("refresh");
  // A user navigation made while metadata refresh was pending wins over the
  // old selection captured above. Never reset the newly selected project.
  if (gen !== generation) return;
  directoryRows = null; directoryPath = "";
  apply(d);
  if (!source && dir) {
    const requested = dir, children = await api("list", { path: requested });
    if (gen !== generation) return;
    directoryRows = children; directoryPath = requested;
  }
  project = projectEntries(d.snapshot).find((e) => e.path === p) || null;
  current = project || source ? c : "";
  await load();
}
function selectedItems() {
  return visibleRows.filter((e) => selected.has(e.path));
}
function select(e, event) {
  if (!e) return;
  let index = visibleRows.findIndex((x) => x.path === e.path);
  if (event.shiftKey && anchor !== null) {
    let start = Math.min(anchor, index),
      end = Math.max(anchor, index);
    if (!event.ctrlKey && !event.metaKey) selected.clear();
    for (const x of visibleRows.slice(start, end + 1)) selected.add(x.path);
  } else if (event.ctrlKey || event.metaKey) {
    if (selected.has(e.path)) selected.delete(e.path);
    else selected.add(e.path);
    anchor = index;
  } else {
    selected = new Set([e.path]);
    anchor = index;
  }
  syncSelection();
}
function syncSelection() {
  for (const el of $$('[data-file], [data-project]')) {
    const path = el.dataset.file || el.dataset.project;
    const active = el.dataset.project && selectionPane !== "projects" ? activeFolder()?.path === path : selected.has(path);
    el.classList.toggle("selected", active);
    el.setAttribute("aria-selected", String(active));
  }
  $("#selected-count").textContent = `已选 ${selected.size} 项`;
  $("#batch-tools").hidden = selectionPane === "projects" || selected.size < 2;
}
for (const pane of ["projects", "files"])
  $("#" + pane).addEventListener("focusin", () => {
    if (selectionPane !== pane) { focusPane(pane); syncSelection(); }
  });
$("#query").addEventListener("compositionstart", () => (composing = true));
let composing = false,
  timer;
$("#query").addEventListener("compositionend", () => {
  composing = false;
  submitQuery();
});
$("#query").addEventListener("input", () => {
  if (!composing) submitQuery();
});
function submitQuery() {
  clearTimeout(timer);
  timer = setTimeout(() => {
    query = $("#query").value;
    selected.clear();
    render();
  }, 50);
}
$("#clear-query").onclick = () => {
  $("#query").value = "";
  query = "";
  selected.clear();
  render();
};
$("#directories").onclick = async (e) => {
  const b = e.target.closest("[data-dir], [data-rail-file]");
  if (!b) return;
  resetClassification(); operationPane = "directories";
  railFile = b.dataset.railFile || "";
  dir = b.dataset.dir || b.dataset.orderRoot;
  const gen = ++generation;
  directoryRows = null; directoryPath = "";
  selectionPane = "projects"; anchor = null; folderError = ""; folderLoading = false;
  source = null;
  sourceFolder = null; sourcePreviewCurrent = ""; sourceChildren = []; previewLoading = false; sourceGeneration++;
  project = null;
  current = "";
  rows = [];
  selected.clear();
  rail();
  render();
  try {
    const children = await api("list", { path: dir });
    if (gen !== generation) return;
    // Normal linked folders already have an indexed direct-child snapshot.
    // Only use a transient list for lazy drive folders absent from that index.
    const indexed = [...data.snapshot.rootEntries, ...data.snapshot.projects].filter(p => p.directory === dir);
    directoryRows = indexed.length || data.settings.roots.includes(dir) ? null : children;
    directoryPath = directoryRows ? dir : "";
    if (railFile) selected.add(railFile);
    render();
  } catch (error) { if (gen === generation) toast(error.message, true); }
};
$("#directories").ondblclick = e => {
  const file = e.target.closest("[data-rail-file]")?.dataset.railFile;
  if (file) action(() => api("open", { path: file }));
};
$("#sources").onclick = (e) => {
  const b = e.target.closest("[data-source]");
  if (!b) return;
  action(async () => {
    resetClassification(); operationPane = "projects";
    generation++; anchor = null; folderError = ""; folderLoading = false;
    selected.clear(); rows = [];
    source = data.settings.sources.find((s) => s.id === b.dataset.source);
    sourceFolder = null; sourcePreviewCurrent = ""; sourceChildren = []; previewLoading = false; selectionPane = "projects"; sourceGeneration++;
    project = null;
    current = source.kind==='folder' ? source.path : "";
    rail();
    await previewLoad;
    await load();
  });
};
function showMiddleFolder(item) {
  resetClassification();
  const gen = ++generation, sourceID = source?.id;
  sourceGeneration++;
  folderError = "";
  project = !source && item?.folder ? item : null;
  if (source) {
    sourceFolder = item?.folder ? item : null;
    sourcePreviewCurrent = sourceFolder?.path || "";
    sourceChildren = [];
    previewLoading = !!sourceFolder;
  } else {
    current = project?.path || "";
    rows = [];
    folderLoading = !!project;
  }
  render();
  if (!item?.folder) return Promise.resolve();
  previewLoad = api("list", { path: item.path }).then(children => {
    if (gen !== generation || source?.id !== sourceID || activeFolder()?.path !== item.path) return;
    if (source) { sourceChildren = children; previewLoading = false; }
    else { rows = children; folderLoading = false; }
    render();
  }).catch(error => {
    if (gen !== generation || source?.id !== sourceID || activeFolder()?.path !== item.path) return;
    folderError = error.message; previewLoading = false; folderLoading = false; render();
  });
  return previewLoad;
}
function selectMiddle(item, event) {
  focusPane("projects");
  select(item, event);
  const active = selected.has(item.path) ? item : selectedItems().at(-1);
  const location = source ? sourcePreviewCurrent : current;
  if (active?.folder && activeFolder()?.path === active.path && location === active.path && !folderError) { render(); return previewLoad; }
  return showMiddleFolder(active);
}
async function openMiddleFolder(item) {
  if (activeFolder()?.path !== item.path || folderError) {
    focusPane("projects"); selected = new Set([item.path]);
    await showMiddleFolder(item);
  } else await previewLoad;
  if (activeFolder()?.path !== item.path || folderError) return;
  focusPane("files"); render(); $("#files").focus({ preventScroll: true });
}
$("#projects").onclick = (event) => {
  const row = event.target.closest("[data-project]");
  if (!row) {
    focusPane("projects"); selected.clear(); anchor = null; render();
    if (event.target.id === "empty-settings") settings();
    if (event.target.id === "demo") action(async () => apply(await api("demo")));
    return;
  }
  const item = middleRows.find(e => e.path === row.dataset.project);
  if (item) selectMiddle(item, event);
};
$("#projects").ondblclick = event => {
  const row = event.target.closest("[data-project]");
  const item = middleRows.find(e => e.path === row?.dataset.project);
  if (!item) return;
  if (item.folder) openMiddleFolder(item);
  else action(() => api("open", { path: item.path }));
};
$("#files").onclick = (e) => {
  const b = e.target.closest("[data-file]"),
    g = e.target.closest("[data-group]");
  if (b) {
    focusPane("files");
    select(fileRows.find((x) => x.path === b.dataset.file), e);
  }
  else if (g) {
    focusPane("files");
    collapsed.has(g.dataset.group)
      ? collapsed.delete(g.dataset.group)
      : collapsed.add(g.dataset.group);
    render();
  } else if (e.target.id === "empty-categories") settings("文件分类");
  else { focusPane("files"); selected.clear(); anchor = null; render(); $("#files").focus({ preventScroll: true }); }
};
function openFileItem(item) {
  if (!item) return;
  action(async () => {
    if (item.folder) {
      resetClassification();
      if (source) {
        const gen = ++sourceGeneration;
        const children = await api("list", { path: item.path });
        if (gen !== sourceGeneration || !source || !sourceFolder) return;
        sourcePreviewCurrent = item.path;
        sourceChildren = children;
        selected.clear(); selectionPane = "files"; render();
        return;
      }
      if (query) {
        project = [...(data.snapshot.rootEntries || []), ...data.snapshot.projects].find((p) => p.path === item.project);
        query = "";
        $("#query").value = "";
      }
      current = item.path;
      await load();
    } else await api("open", { path: item.path });
  });
}
$("#files").ondblclick = (e) => {
  const p = e.target.closest("[data-file]")?.dataset.file;
  openFileItem(fileRows.find((x) => x.path === p));
};
function renderBreadcrumbs(root, bar = "#subnav", title = "项目根目录", location = current) {
  const parts = GuiyuNavigation.breadcrumbs(root, location, title);
  if (parts.length < 2) return;
  const rootIcon = '<svg width="14" height="14" viewBox="0 0 20 20" aria-hidden="true"><path d="M2.5 6V4.5h6l2 2h7v10h-15Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  $(bar).innerHTML = `<button id="up" aria-label="上一级" title="上一级：${esc(parts.at(-2).name)}"><svg width="16" height="16" viewBox="0 0 20 20" aria-hidden="true"><path d="m12 4-6 6 6 6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button><nav class="breadcrumbs" aria-label="文件夹路径"><ol>${parts.map((part, i) => `<li><button class="breadcrumb" data-breadcrumb="${i}" title="${esc(parts.slice(0, i+1).map(p=>p.name).join(' / '))}"${i === parts.length - 1 ? ' aria-current="location" disabled' : ''}>${i === 0 ? rootIcon : ''}<span class="breadcrumb-label">${esc(part.name)}</span></button></li>`).join("")}</ol></nav><button id="path-menu" aria-label="选择路径层级" title="选择任意上级目录"><svg width="16" height="16" viewBox="0 0 20 20" aria-hidden="true"><circle cx="4" cy="10" r="1.5" fill="currentColor"/><circle cx="10" cy="10" r="1.5" fill="currentColor"/><circle cx="16" cy="10" r="1.5" fill="currentColor"/></svg></button>`;
  const navigation = $(bar+" .breadcrumbs");
  navigation.scrollLeft = navigation.scrollWidth;
}
function breadcrumbClick(e) {
  const bar = e.currentTarget.id === "source-subnav" ? "#source-subnav" : "#subnav";
  const fromSource = bar === "#source-subnav";
  const button = e.target.closest("#up, #path-menu, [data-breadcrumb]");
  if (!button) return;
  const preview = !fromSource && !!source && !!sourceFolder;
  const root = fromSource ? source?.path : preview ? sourceFolder.path : project?.path;
  const parts = GuiyuNavigation.breadcrumbs(root, preview ? sourcePreviewCurrent : current, fromSource ? source.name : preview ? sourceFolder.name : "项目根目录");
  if (button.id === "path-menu") {
    const rect = button.getBoundingClientRect();
    menu({ preventDefault() {}, clientX: rect.left, clientY: rect.bottom }, parts.map((part, i) => ({
      label: part.name, disabled: i === parts.length - 1,
      fn: () => $(bar+" [data-breadcrumb=\"" + i + "\"]")?.click(),
    })));
    return;
  }
  const index = button.id === "up" ? parts.length - 2 : Number(button.dataset.breadcrumb);
  const target = parts[index]?.path;
  if (!target || index === parts.length - 1) return;
  action(async () => {
    const sourceID = source?.id, owner = root;
    resetClassification();
    const gen = fromSource || preview ? ++sourceGeneration : ++generation;
    await api('closePreview');
    const children = fromSource && target===source.path ? await api('source',{id:source.id}) : await api("list", { path: target });
    if (fromSource) {
      if (gen !== sourceGeneration || source?.id !== sourceID || source?.path !== owner) return;
      rows = children;
      sourceFolder = null; sourcePreviewCurrent = ""; sourceChildren = []; previewLoading = false;
      selectionPane = "projects";
    } else if (preview) {
      if (gen !== sourceGeneration || source?.id !== sourceID || sourceFolder?.path !== owner) return;
      sourceChildren = children;
      sourcePreviewCurrent = target;
      selectionPane = "files";
    } else {
      if (gen !== generation || source || project?.path !== owner) return;
      rows = children;
    }
    if (!preview) current = target;
    selected.clear();
    anchor = null;
    render();
    (fromSource ? $("#projects") : $("#files")).focus({ preventScroll: true });
  });
}
$("#subnav").onclick = breadcrumbClick;
$("#source-subnav").onclick = breadcrumbClick;

$$("[data-mode]").forEach(
  (b) =>
    (b.onclick = () => {
      mode = b.dataset.mode;
      if (mode === "按类别") recentCopies.clear();
      collapsed.clear();
      selected.clear();
      render();
    }),
);
$("#sort").onchange = (e) => {
  sort = e.target.value;
  render();
};
$("#refresh").onclick = () => action(refresh);
$("#add-root").onclick = () => action(async () => apply(await api("addRoots")));
$("#add-source").onclick = () =>
  action(async () => apply(await api("addSource")));
$("#settings").onclick = () => settings();
$("#select-all").onclick = () => {
  selected = new Set(visibleRows.map((e) => e.path));
  render();
};
$("#deselect").onclick = () => {
  selected.clear();
  render();
};
function menu(event, items) {
  event.preventDefault();
  const el = $("#context");
  el.innerHTML = items
    .map((i, n) =>
      i
        ? `<button role="menuitem" data-menu="${n}" ${i.disabled ? 'disabled' : ''}>${esc(i.label)}</button>`
        : "<hr>",
    )
    .join("");
  el.hidden = false;
  el.style.left = Math.min(event.clientX, innerWidth - 250) + "px";
  el.style.top =
    Math.min(event.clientY, innerHeight - el.offsetHeight - 8) + "px";
  el.onclick = (e) => {
    let n = e.target.closest("[data-menu]")?.dataset.menu;
    if (n === undefined || items[n].disabled) return;
    el.hidden = true;
    items[n].fn();
  };
  el.querySelector("button")?.focus();
}
async function fileMenu(ev, items, archive = false) {
  $("#context").hidden = true;
  if (!items.length) return;
  let actions = [
    {
      label: items.length > 1 ? "批量智能命名…" : "智能命名…",
      fn: () => namingDialog(items, true),
    },
    {
      label: items.length > 1 ? "批量更改名称…" : "更改名称…",
      fn: () => namingDialog(items, false),
    },
  ];
  if (archive)
    actions.push({ label: "智能归档…", fn: () => archiveDialog(items) });
  else
    for (const c of data.settings.categories)
      if (!items.every((e) => category(e) === c.id))
        actions.push({
          label: `移动到「${c.name}」`,
          fn: () =>
            action(async () => apply(await api("assign", { items, id: c.id }))),
        });
  actions.push(
    null,
    {
      label: "在资源管理器中显示",
      fn: () => action(() => api("reveal", { path: items[0].path })),
    },
    {
      label: "移到回收站",
      fn: () =>
        action(async () => {
          apply(await api("trash", { items }));
          await load();
        }),
    },
  );
  const clipboard = await clipboardActions(items);
  if (!$("#modal").open) menu(ev, [...clipboard, ...actions]);
}
$("#files").oncontextmenu = async (e) => {
  e.preventDefault();
  $("#context").hidden = true;
  focusPane("files");
  const p = e.target.closest("[data-file]")?.dataset.file;
  if (p) {
    if (!selected.has(p)) selected = new Set([p]);
    render();
    fileMenu(e, selectedItems(), !!source);
  } else menu(e, await clipboardActions());
};
$("#projects").oncontextmenu = async event => {
  event.preventDefault();
  $("#context").hidden = true;
  focusPane("projects");
  const row = event.target.closest("[data-project]");
  const item = middleRows.find(e => e.path === row?.dataset.project);
  if (!item) { selected.clear(); render(); return menu(event, await clipboardActions()); }
  if (!selected.has(item.path)) selected = new Set([item.path]);
  render();
  fileMenu(event, selectedItems(), !!source);
};
$("#batch-menu").onclick = (e) => fileMenu(e, selectedItems(), !!source);
document.addEventListener("pointerdown", (e) => {
  if (!e.target.closest("#context")) $("#context").hidden = true;
});
$("#directories").oncontextmenu = async (e) => {
  e.preventDefault();
  $("#context").hidden = true;
  const button = e.target.closest("[data-dir], [data-rail-file]");
  if (!button) return;
  await $("#directories").onclick({ target: button });
  const d = button.dataset.dir || button.dataset.railFile;
  menu(e, [...await clipboardActions([{ path: d }]),
      {
        label: "在资源管理器中显示",
        fn: () => action(() => api("reveal", { path: d })),
      },
    ]);
};
$("#sources").oncontextmenu = (e) => {
  let id = e.target.closest("[data-source]")?.dataset.source;
  if (id)
    menu(e, [
      {
        label: "移除关联",
        fn: () =>
          action(async () => {
            apply(await api("removeSource", { id }));
            source = null;
            rows = [];
            render();
          }),
      },
    ]);
};
function close() {
  if (!working) $("#modal").close();
}
function modal(html) {
  $("#context").hidden = true;
  $("#modal-content").innerHTML = html;
  if (!$("#modal").open) $("#modal").showModal();
  $$("[data-cancel]").forEach((b) => (b.onclick = close));
}
function errorIn(e) {
  const el = $("#dialog-error");
  if (el) el.textContent = e.message;
  else toast(e.message, true);
}
function actions(confirm, withArchive = false) {
  return `<div id="dialog-error" class="inline-error" role="alert"></div><div class="dialog-actions"><button data-cancel>取消</button>${withArchive ? '<button id="confirm-archive">确认并归档</button>' : ''}<button id="confirm" class="primary">${confirm}</button></div>`;
}
function smartHeader(title, symbol) {
  return `<div class="smart-header"><span class="smart-header-icon" aria-hidden="true">${symbol}</span><h2>${title}</h2></div>`;
}
function namingLoadingDialog(entry) {
  return `<div class="dialog-body smart-dialog naming-preview-dialog" aria-busy="true">${smartHeader("智能命名", "✎")}
    <div class="naming-workspace">
      <section class="preview-panel">
        <div class="preview-panel-heading"><h3>文件预览</h3><span class="muted preview-filename" title="${esc(entry.name)}">${esc(entry.name)}</span></div>
        <div class="preview-pages" role="tablist" aria-label="预览页码"><button disabled role="tab" aria-selected="true">第 1 页</button><button disabled role="tab" aria-selected="false">第 2 页</button></div>
        <div class="document-preview"><div class="naming-loading" role="status"><span class="naming-spinner" aria-hidden="true"></span><span>正在准备文件预览…</span></div></div>
        <div class="preview-hint muted">识别完成后可在页面上框选文字。</div>
      </section>
      <section class="naming-side">
        <div class="recognized-panel"><h3>识别文字</h3><textarea aria-label="识别文字" placeholder="在左侧框选要识别的文字" disabled></textarea><div class="recognized-actions"><span class="muted">正在准备，请稍候</span><button type="button" disabled>使用识别文字</button></div></div>
        <div class="recommend-panel"><h3>推荐名称</h3><div class="scroll candidate-list"><div class="naming-loading" role="status"><span class="naming-spinner" aria-hidden="true"></span><span>正在生成推荐名称…</span></div></div><div class="name-editor"><label for="loading-name">最终文件名</label><div class="naming-line"><input id="loading-name" placeholder="识别完成后可编辑" disabled></div></div></div>
      </section>
    </div>${actions("确认重命名", true)}</div>`;
}
async function namingDialog(items, smart) {
  modal(smart && items.length === 1 ? namingLoadingDialog(items[0]) : `<div class="dialog-body" style="height:460px"><h2>${smart ? "智能命名" : "更改名称"}</h2><p class="muted">正在准备${items.length}个条目…</p>${actions("确认重命名", smart)}</div>`);
  $("#confirm").disabled = true;
  if ($("#confirm-archive")) $("#confirm-archive").disabled = true;
  const pending = $("#modal-content").firstElementChild;
  let suggestions;
  try {
    suggestions = smart ? await api("naming", { items }) : items.map((entry) => ({
      entry, ext: entry.folder ? "" : entry.name.match(/\.[^.]+$/)?.[0] || "",
      prefix: "", candidates: [],
    }));
  } catch (e) { if (pending.isConnected) errorIn(e); return; }
  if (!$("#modal").open || !pending.isConnected) return;
  const batch = items.length > 1;
  const editor = (r, c) => GuiyuNaming.candidateEditor(r, c);
  const batchEditor = (r, c) => GuiyuNaming.candidateBatch(r, c);
  let body = `<div class="dialog-body ${smart && !batch ? "smart-dialog naming-preview-dialog" : batch ? "batch-dialog" : "direct-dialog"}" ${smart && !batch ? "" : `style="height:${batch ? 600 : 460}px"`}>${smart && !batch ? smartHeader("智能命名", "✎") : `<h2>${batch ? "批量" : ""}${smart ? "智能命名" : "更改名称"}</h2>`}`;
  if (!batch) {
    const r = suggestions[0], e = r.entry;
    const stem = smart ? editor(r, r.candidates[0]) : GuiyuNaming.literalStem(e.name, r.ext);
    const prefix = smart && !r.fallback && r.format === "month"
      ? `<input class="month" id="name-prefix" aria-label="月份" type="number" min="1" max="12" value="${parseInt(r.prefix)}"><span>月</span>`
      : smart && !r.fallback && r.format === "monthDay" ? `<span id="fixed-prefix">${esc(r.prefix)}</span>` : "";
    if (smart) {
      body += `<div class="naming-workspace"><section class="preview-panel"><div class="preview-panel-heading"><h3>文件预览</h3><span class="muted preview-filename" title="${esc(e.name)}">${esc(e.name)}</span></div><div class="preview-pages" role="tablist" aria-label="预览页码"><button data-preview-page="0" role="tab" aria-selected="true">第 1 页</button><button data-preview-page="1" role="tab" aria-selected="false">第 2 页</button></div><div id="document-preview" class="document-preview" aria-label="文件页面预览"><p class="muted">正在准备页面预览…</p></div><div class="preview-hint muted" id="preview-hint">在页面上拖动选取文字，也可以在右侧修改识别结果。</div></section><section class="naming-side"><div class="recognized-panel"><h3>识别文字</h3><textarea id="recognized-text" aria-label="识别文字" placeholder="页面文字正在识别…"></textarea><div class="recognized-actions"><span id="selection-hint" class="muted">选取需要用于命名的文字</span><button id="use-text" type="button">使用选中文字</button></div></div><div class="recommend-panel"><h3>推荐名称</h3><div class="scroll candidate-list">${r.candidates.map((c, i) => `<button class="candidate ${i === 0 ? "chosen" : ""}" aria-pressed="${i === 0}" data-candidate="${i}" title="${esc(c.evidence)}"><span aria-hidden="true" class="choice-mark"></span><span>${esc(editor(r, c))}<small>${esc(c.evidence || "文档标题")}</small></span></button>`).join("") || '<p class="muted">未找到明确标题，可从页面选字或手动输入。</p>'}</div><div class="name-editor"><label for="name-stem">最终文件名</label><div class="naming-line">${prefix}<input id="name-stem" aria-label="最终文件名" value="${esc(stem)}"><span>${esc(r.ext)}</span></div></div></div></section></div>`;
    } else {
      body += `<div class="original-name"><span class="muted">原名称</span><div>${esc(e.name)}</div></div><div class="name-editor"><label for="name-stem">新名称</label><div class="naming-line">${prefix}<input id="name-stem" aria-label="识别的名称" value="${esc(stem)}"><span>${esc(r.ext)}</span></div></div><p class="muted">更改后：<span id="direct-preview">${esc(stem + r.ext)}</span></p><p class="muted">确认后同步更改本机名称，保留扩展名，同名不覆盖。</p>`;
    }
    if (r.warnings?.length) body += `<div class="muted">部分文档未能提取，您可以手工填写；详情见提示。<span title="${esc(r.warnings.join("\n"))}">ⓘ</span></div>`;
  } else {
    body += `<p class="muted batch-description">逐项核对并修改新名称；取消勾选可跳过。确认后同步更改本机名称，同名不覆盖。 <span id="batch-count">${suggestions.filter(r=>!smart||!r.fallback).length} / ${suggestions.length} 项</span></p>`;
    if (!smart) body += '<div class="setting-form"><input id="find" placeholder="查找文字" aria-label="查找文字"><input id="replace" placeholder="替换为" aria-label="替换为"><input id="prefix" placeholder="添加前缀" aria-label="添加前缀"><button id="apply-batch">应用</button></div>';
    body += '<div class="scroll">' + suggestions.map((r, i) => `<div class="batch-original">${esc(r.entry.name)}</div><div class="batch-row"><input type="checkbox" data-include="${i}" aria-label="处理 ${esc(r.entry.name)}" ${smart && r.fallback ? "" : "checked"}><input type="text" data-name="${i}" aria-label="新名称 ${esc(r.entry.name)}" value="${esc(smart ? batchEditor(r, r.candidates[0]) : GuiyuNaming.literalStem(r.entry.name, r.ext))}"><span>${esc(r.ext)}</span>${smart ? `<select data-alternate="${i}" aria-label="其他候选"><option value="">其他候选</option>${r.candidates.map((c, j) => `<option value="${j}">${esc(batchEditor(r, c))}</option>`).join("")}</select>` : ""}</div>`).join("") + '</div>';
  }
  modal(body + actions("确认重命名", smart) + '</div>');
  const confirm = $("#confirm"), confirmArchive = $("#confirm-archive");
  const namingPanel = $("#modal-content").firstElementChild;
  let submitting = false, partial = false;
  function canSubmit() {
    const active = suggestions.filter((r, i) => !batch || $(`[data-include="${i}"]`).checked);
    return active.length > 0 && active.every((r) => {
      const i = suggestions.indexOf(r), value = batch ? $(`[data-name="${i}"]`).value : $("#name-stem").value;
      return GuiyuNaming.literalStem(value.trim(), r.ext).trim().length > 0;
    });
  }
  function updateEditor() {
    confirm.disabled = submitting || partial || !canSubmit();
    if (confirmArchive) confirmArchive.disabled = confirm.disabled;
    if (!batch && smart) $$('[data-candidate]').forEach((button) => {
      const chosen = editor(suggestions[0], suggestions[0].candidates[+button.dataset.candidate]) === $("#name-stem").value;
      button.classList.toggle('chosen', chosen); button.setAttribute('aria-pressed', String(chosen));
    });
    if (!batch && !smart) $("#direct-preview").textContent = $("#name-stem").value + suggestions[0].ext;
    if (batch) $("#batch-count").textContent = `${$$('[data-include]:checked').length} / ${suggestions.length} 项`;
  }
  $$('[data-candidate]').forEach((button) => button.onclick = () => {
    $("#name-stem").value = editor(suggestions[0], suggestions[0].candidates[+button.dataset.candidate]);
    updateEditor();
  });
  if (smart && !batch) {
    const panel = $(".naming-preview-dialog"), pages = new Map();
    let pageIndex = 0, requestId = 0, dragging = null, recognizing = false;
    const textarea = $("#recognized-text"), preview = $("#document-preview");
    const tabs = $$('[data-preview-page]');
    textarea.value = "";
    textarea.placeholder = "在左侧页面拖动框选需要识别的文字";
    $("#use-text").textContent = "使用识别文字";
    $("#selection-hint").textContent = "框选后可在这里修改识别结果";
    const drawPage = (p) => {
      if (!p.supported) {
        preview.innerHTML = `<p class="preview-message muted">${esc(p.message)}</p>`;
        tabs.forEach(t => t.disabled = true); textarea.placeholder = "当前文件暂不支持页面文字预览";
        return;
      }
      tabs.forEach((t, i) => { t.disabled = i >= p.pageCount; t.setAttribute("aria-selected", String(i === pageIndex)); });
      textarea.value = p.text || "";
      preview.innerHTML = `<div class="preview-page region-select-page"><img alt="第 ${pageIndex + 1} 页" draggable="false" src="data:image/png;base64,${p.image}"><div class="region-box" hidden></div></div>`;
      if (p.region) paintBox(p.region);
      $("#preview-hint").textContent = "在页面上拖动框选文字，松开后自动识别。";
    };
    function paintBox(region) {
      const box = preview.querySelector(".region-box");
      if (!box) return;
      box.hidden = false;
      Object.assign(box.style, { left: (region.x * 100) + "%", top: (region.y * 100) + "%", width: (region.w * 100) + "%", height: (region.h * 100) + "%" });
    }
    function point(event, page) {
      const r = page.getBoundingClientRect();
      return { x: Math.max(0, Math.min(1, (event.clientX - r.left) / r.width)), y: Math.max(0, Math.min(1, (event.clientY - r.top) / r.height)) };
    }
    function rectangle(a, b) { return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(a.x - b.x), h: Math.abs(a.y - b.y) }; }
    async function showPage(index) {
      if (pages.has(pageIndex) && pages.get(pageIndex).supported) pages.get(pageIndex).text = textarea.value;
      pageIndex = index; $("#selection-hint").textContent = "框选后可在这里修改识别结果";
      if (pages.has(index)) { drawPage(pages.get(index)); return; }
      const id = ++requestId;
      tabs.forEach(t => t.disabled = true);
      preview.innerHTML = '<p class="preview-message muted">正在本地加载页面…</p>';
      try {
        const result = await api("namingPreview", { entry: suggestions[0].entry, page: index });
        if (!panel.isConnected || id !== requestId) return;
        pages.set(index, result); drawPage(result);
      } catch (e) {
        if (!panel.isConnected || id !== requestId) return;
        preview.innerHTML = `<p class="preview-message muted">${esc(e.message)}</p>`;
        $("#preview-hint").textContent = "您仍可以手动输入文件名。";
        tabs.forEach((t, i) => { t.disabled = i === index; });
      }
    }
    tabs.forEach(t => t.onclick = () => showPage(+t.dataset.previewPage));
    preview.onpointerdown = event => {
      const page = event.target.closest(".region-select-page");
      if (!page || recognizing || event.button !== 0) return;
      event.preventDefault();
      dragging = { page, start: point(event, page), pointer: event.pointerId };
      page.setPointerCapture(event.pointerId);
      paintBox(rectangle(dragging.start, dragging.start));
    };
    preview.onpointermove = event => {
      if (!dragging || dragging.pointer !== event.pointerId) return;
      paintBox(rectangle(dragging.start, point(event, dragging.page)));
    };
    preview.onpointercancel = () => { dragging = null; };
    preview.onpointerup = async event => {
      if (!dragging || dragging.pointer !== event.pointerId) return;
      const region = rectangle(dragging.start, point(event, dragging.page));
      dragging = null;
      if (region.w < 0.01 || region.h < 0.005) { preview.querySelector(".region-box").hidden = true; $("#selection-hint").textContent = "框选范围太小，请重新框选。"; return; }
      pages.get(pageIndex).region = region;
      textarea.value = "";
      textarea.placeholder = "正在识别框选区域…";
      $("#selection-hint").textContent = "正在本地识别框选区域…";
      recognizing = true;
      tabs.forEach(t => t.disabled = true);
      const id = ++requestId;
      try {
        const result = await api("namingRecognizeRegion", { entry: suggestions[0].entry, page: pageIndex, region });
        if (!panel.isConnected || id !== requestId) return;
        const cleaned = GuiyuNaming.cleanRecognizedText(result);
        textarea.value = cleaned;
        pages.get(pageIndex).text = cleaned;
        textarea.placeholder = "未识别到文字，可重新框选或手动输入";
        $("#selection-hint").textContent = cleaned ? "已识别框选区域，可修改后用于命名" : "未识别到文字，请重新框选或手动输入";
      } catch (e) {
        if (!panel.isConnected || id !== requestId) return;
        textarea.placeholder = "识别失败，可重新框选或手动输入";
        $("#selection-hint").textContent = e.message;
      } finally {
        recognizing = false;
        if (panel.isConnected && id === requestId) tabs.forEach((t, i) => { t.disabled = i >= pages.get(pageIndex).pageCount; });
      }
    };
    textarea.oninput = () => { $("#selection-hint").textContent = "可修改文字，点击按钮用于命名"; };
    $("#use-text").onclick = () => {
      const selection = textarea.value.slice(textarea.selectionStart, textarea.selectionEnd).trim();
      const text = selection || textarea.value.trim();
      if (!text) { $("#selection-hint").textContent = "请先框选或输入文字。"; return; }
      $("#name-stem").value = GuiyuNaming.cleanRecognizedText(text);
      updateEditor();
    };
    showPage(0);
  }
  $$('[data-alternate]').forEach((select) => select.onchange = () => {
    if (select.value !== '') { const i = +select.dataset.alternate;
      $(`[data-name="${i}"]`).value = batchEditor(suggestions[i], suggestions[i].candidates[+select.value]); updateEditor(); }
  });
  $$('[data-include]').forEach((input) => input.onchange = updateEditor);
  $$('#modal input[type="text"], #name-stem').forEach((input) => {
    input.oninput = updateEditor;
    input.onkeydown = (e) => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); if (!confirm.disabled) confirm.click(); } };
  });
  if ($("#apply-batch")) $("#apply-batch").onclick = () => {
    suggestions.forEach((r, i) => {
      if (!$(`[data-include="${i}"]`).checked) return;
      let stem = GuiyuNaming.literalStem(r.entry.name, r.ext), find = $("#find").value;
      if (find) stem = stem.split(find).join($("#replace").value);
      $(`[data-name="${i}"]`).value = $("#prefix").value + stem;
    }); updateEditor();
  };
  updateEditor();
  const modalElement = $("#modal");
  const preventPendingCancel = (event) => { if (submitting) event.preventDefault(); };
  async function submit(andArchive = false) {
    if (submitting || partial || !canSubmit()) return;
    submitting = true;
    modalElement.addEventListener("cancel", preventPendingCancel);
    $("#dialog-error").textContent = "";
    if (smart && !batch) window.guiyu?.cancelNaming?.();
    updateEditor();
    const cancelButtons = $$('[data-cancel]');
    cancelButtons.forEach(b => b.disabled = true);
    let renamed = false;
    try {
      if(!andArchive && smart && !batch && suggestions[0].fallback && $("#name-stem").value===GuiyuNaming.literalStem(suggestions[0].entry.name,suggestions[0].ext)){ $("#modal").close(); return; }
      const plans = suggestions.flatMap((r, i) => {
        if (batch && !$(`[data-include="${i}"]`).checked) return [];
        let stem = batch ? $(`[data-name="${i}"]`).value : $("#name-stem").value;
        if (!batch && smart && !r.fallback && ["month", "monthDay"].includes(r.format)) {
          const prefix = r.format === 'month' ? $("#name-prefix").value + '月' : r.prefix;
          stem = prefix + ' ' + stem;
        }
        const name = GuiyuNaming.editedName(stem, r.ext, smart);
        if (smart && !r.fallback) GuiyuNaming.validatePrefix(name, r.format);
        return [{ entry: r.entry, name, smart: smart && !r.fallback }];
      });
      const result = await api('rename', { plans, ...(andArchive ? { forArchive: true } : {}) });
      renamed = true;
      if (!namingPanel.isConnected || !modalElement.open) return;
      for (const p of plans) if (selected.delete(p.entry.path))
        selected.add(p.entry.path.slice(0, p.entry.path.length - p.entry.name.length) + p.name);
      const renamedSelection = [...selected];
      for (const p of plans) if (p.entry.folder) {
        const target = p.entry.path.slice(0, p.entry.path.length - p.entry.name.length) + p.name;
        if (project?.path === p.entry.path) project = [...(result.snapshot.rootEntries || []), ...result.snapshot.projects].find((x) => x.path === target) || null;
        if (current === p.entry.path || current.startsWith(p.entry.path + '\\') || current.startsWith(p.entry.path + '/')) current = target + current.slice(p.entry.path.length);
        if (sourcePreviewCurrent === p.entry.path || sourcePreviewCurrent.startsWith(p.entry.path + '\\') || sourcePreviewCurrent.startsWith(p.entry.path + '/')) sourcePreviewCurrent = target + sourcePreviewCurrent.slice(p.entry.path.length);
        if (sourceFolder?.path === p.entry.path) sourceFolder = { ...sourceFolder, path: target, name: p.name };
      }
      apply(result);
      try { await load(); } catch (e) { toast(`命名已完成，列表刷新失败：${e.message}`, true); }
      selected = new Set(renamedSelection.filter(p => visibleRows.some(e => e.path === p)));
      syncSelection();
      if (andArchive) {
        if (!result.renamedItems?.length) throw Error("命名已完成，但未能取得归档文件信息，请关闭窗口后重新选择。");
        modalElement.removeEventListener("cancel", preventPendingCancel);
        await archiveDialog(result.renamedItems);
      } else $("#modal").close();
      if (result.result) toast(`已重命名 ${result.result} 项`);
    } catch (e) {
      errorIn(e); if (renamed || /已完成\s*[1-9]\d*\s*项/.test(e.message)) partial = true;
    } finally {
      submitting = false;
      cancelButtons.forEach(b => b.disabled = false);
      modalElement.removeEventListener("cancel", preventPendingCancel);
      if (namingPanel.isConnected) updateEditor();
    }
  }
  confirm.onclick = () => submit(false);
  if (confirmArchive) confirmArchive.onclick = () => submit(true);
}
async function archiveDialog(items) {
  modal(
    `<div class="dialog-body smart-dialog archive-dialog" style="height:620px">${smartHeader("智能归档", "⇩")}<div class="file-summary">${icon(items[0] || { name: "" })}<span>${esc(items[0]?.name || "")}${items.length > 1 ? ` 等 ${items.length} 项` : ""}<small>${items.length} 项待归档</small></span></div><input id="archive-query" placeholder="搜索项目名、单位词或关键词" aria-label="搜索归档项目"><div class="scroll" id="archive-projects">正在查找推荐项目…</div>${actions("确认归档")}</div>`,
  );
  $("#confirm").disabled = true;
  let results;
  try {
    results = await api("archiveSuggest", { items });
  } catch (e) {
    errorIn(e);
    return;
  }
  if (!$("#modal").open) return;
  let target = null;
  function draw() {
    target = null;
    $("#confirm").disabled = true;
    let q = $("#archive-query").value;
    const filtered = results.projects.filter(p => q.trim() ? match(p.name, q) : p.score >= 75);
    $("#archive-projects").innerHTML =
      filtered
        .map(
          (p, i) =>
            `${i === 0 ? `<h3>${q ? "搜索结果" : p.score > 0 ? "匹配项目" : "全部项目"}</h3>` : !q && p.score === 0 && filtered[i - 1]?.score > 0 ? "<h3>其他项目</h3>" : ""}<button class="archive-choice" aria-pressed="false" data-target="${esc(p.path)}" title="${esc(p.evidence)}">${folder}<span class="name-wrap"><span class="name">${esc(p.name)}</span><small>${esc(basename(p.directory))}</small></span><span class="choice-mark" aria-hidden="true"></span></button>`,
        )
        .join("") || `<p class="muted">${q.trim() ? "没有搜索到符合名称的项目，请调整关键词。" : "暂无可靠推荐，请输入项目名或关键词自行搜索。"}</p>`;
    if (results.warnings.length)
      $("#dialog-error").textContent = results.warnings.join("\n");
  }
  draw();
  $("#archive-query").oninput = draw;
  $("#archive-projects").onclick = (e) => {
    let b = e.target.closest("[data-target]");
    if (!b) return;
    target = b.dataset.target;
    $$("[data-target]").forEach((x) => { x.classList.toggle("selected", x === b); x.setAttribute("aria-pressed", String(x === b)); });
    $("#confirm").disabled = false;
  };
  $("#confirm").onclick = async () => {
    if (!target) return;
    const button = $("#confirm");
    button.disabled = true;
    try {
      const result = await api("archive", { items, destination: target });
      $("#modal").close();
      apply(result);
      await load();
      toast(`已归档 ${result.result} 项`);
    } catch (e) {
      errorIn(e);
      if (!/已归档/.test(e.message)) button.disabled = false;
    }
  };
}
function settings(s = "文件位置") {
  section = s;
  drawSettings();
}
function drawSettings() {
  let s = data.settings,
    content = "";
  if (section === "文件位置") {
    content = `<h3>项目总目录 <button id="settings-add-root">关联目录…</button></h3>${s.roots.map((r, i) => `<div class="setting-row">${folder}<span class="label">${esc(basename(r))}<small title="${esc(r)}">${esc(r)}</small></span><button data-remove-root="${i}" aria-label="移除关联 ${esc(basename(r))}">−</button></div>`).join("") || '<p class="muted">关联一个或多个项目总目录，开始浏览。</p>'}<p class="muted">可关联整个磁盘或文件夹；左侧显示其中的直接文件和文件夹。拖动分组或条目，横线出现后松手排序。移除关联保留原文件。</p><h3>可归档目录 <button id="settings-add-source">关联文件夹…</button></h3>${s.sources.map((r, i) => `<div class="setting-row"><span class="label">${esc(r.name)}<small>${esc(r.path || "关联文件夹")}</small></span><button data-remove-source="${i}">移除关联</button></div>`).join("")}<p><button id="restore-sources">恢复默认入口</button></p><h3>资源管理器快捷入口</h3><p class="muted">右键文件或文件夹可直接使用智能命名、智能归档。移动应用目录后请重新安装入口。</p><button id="install-menu">安装右键入口</button> <button id="remove-menu">移除右键入口</button>`;
  } else if (section === "文件分类") {
    content = `<form id="add-category" class="setting-form"><input id="category-name" placeholder="新分类名称" aria-label="分类名称" maxlength="40" required><button class="primary">添加分类</button></form><div class="workflow"><h3>分类设置后，请务必按一下操作。 <button id="guides" aria-label="查看操作图解">ⓘ</button></h3><div class="workflow-step"><span class="step-number">1</span><button id="copy-prompt" class="workflow-primary">复制提示词，去豆包官网</button><span id="copy-status"></span></div><div class="workflow-step"><span class="step-number">2</span><span>把提示词发给豆包，复制豆包的回复。</span></div><div class="workflow-step"><span class="step-number">3</span><button id="import-rules">录入豆包回复</button><span id="import-status"></span></div></div><div class="category-search"><span aria-hidden="true">⌕</span><input id="category-query" placeholder="搜索分类" aria-label="搜索分类"><span class="muted">${s.categories.length} 个分类</span></div><div id="category-list">${categoryList("")}</div>`;
  } else if (section === "命名规则") {
    const options = (v) =>
      ["nameOnly", "month", "monthDay", "category"]
        .map(
          (x, i) =>
            `<option value="${x}" ${x === v ? "selected" : ""}>${["仅识别的名称", "月份 + 识别的名称", "月日 + 识别的名称", "分类 + 识别的名称"][i]}</option>`,
        )
        .join("");
    content = `<div class="settings-card"><h3>文件夹命名</h3><select id="folder-format" aria-label="文件夹命名">${options(s.namingRules.folder)}</select></div><div class="settings-card"><h3>文档命名</h3><select id="document-format" aria-label="文档命名">${options(s.namingRules.document)}</select></div><div class="settings-card"><h3>日期来源</h3><select id="date-source" aria-label="日期来源"><option value="today" ${s.namingRules.dateSource === "today" ? "selected" : ""}>命名当天</option><option value="created" ${s.namingRules.dateSource === "created" ? "selected" : ""}>文件创建日期</option></select><p class="muted">默认不加前缀，保留标题原意和原扩展名。多个标题可选择，找不到则保留原名；可手动修改，确认后才改名。日期按北京时间计算。</p></div>`;
  } else {
    content = s.moves.length
      ? s.moves
          .map(
            (m) =>
              `<div class="setting-row"><span class="label">${esc(basename(m.destination))}<small title="${esc(m.source + " → " + m.destination)}">${esc(m.source)} → ${esc(m.destination)}</small><small>${esc(new Date(m.date).toLocaleString("zh-CN"))}</small></span><button data-undo="${esc(m.id)}" ${m.undone ? "disabled" : ""}>${m.undone ? "已撤销" : "撤销"}</button></div>`,
          )
          .join("")
      : '<p class="muted">还没有归档记录</p>';
  }
  const details = {
    文件位置: "把项目和待整理文件，放在顺手的位置。",
    文件分类: "按你的习惯整理，原文件夹结构保持不变。",
    命名规则: "分别设置文件夹和文档的智能命名格式。",
    归档记录: "查看文件去向，需要时可以撤销归档。",
  };
  modal(
    `<div class="settings-dialog"><aside class="settings-rail"><div class="settings-brand"><img src="../assets/companion.png" alt=""><span>设置</span></div>${Object.keys(
      details,
    )
      .map(
        (k) =>
          `<button data-section="${k}" class="${section === k ? "active" : ""}"><span class="settings-icon" aria-hidden="true">${{文件位置:"▱",文件分类:"▦",命名规则:"✎",归档记录:"◷"}[k]}</span>${k}</button>`,
      )
      .join(
        "",
      )}<div class="version">${esc(data.version)}<br>${esc(data.arch)}<br><button id="check-update">检查更新</button><div id="update-status"></div><p>● 文件留在本机</p></div></aside><main class="settings-main"><h2>${section}</h2><div class="muted">${details[section]}</div><div class="settings-content ${section === "文件分类" ? "category-settings" : section === "文件位置" ? "location-settings" : ""}">${content}</div><div id="dialog-error" class="inline-error" role="alert"></div><div class="dialog-actions"><span class="muted" style="margin-right:auto">本地保存 · 更改即生效</span><button data-cancel class="primary">完成</button></div></main></div>`,
  );
  $$("[data-section]").forEach(
    (b) => (b.onclick = () => settings(b.dataset.section)),
  );
  const update = async (method, arg) => {
    try {
      apply(await api(method, arg));
      drawSettings();
    } catch (e) {
      errorIn(e);
    }
  };
  if ($("#install-menu"))
    $("#install-menu").onclick = async () => {
      try {
        await api("explorerMenu", {});
        toast("已安装资源管理器右键入口");
      } catch (e) {
        errorIn(e);
      }
    };
  if ($("#remove-menu"))
    $("#remove-menu").onclick = async () => {
      try {
        await api("explorerMenu", { remove: true });
        toast("已移除资源管理器右键入口");
      } catch (e) {
        errorIn(e);
      }
    };
  if ($("#settings-add-root"))
    $("#settings-add-root").onclick = () => update("addRoots");
  if ($("#settings-add-source"))
    $("#settings-add-source").onclick = () => update("addSource");
  if ($("#restore-sources"))
    $("#restore-sources").onclick = () => update("restoreSources");
  $$("[data-remove-root]").forEach(
    (b) =>
      (b.onclick = () =>
        update("removeRoot", { path: s.roots[+b.dataset.removeRoot] })),
  );
  $$("[data-remove-source]").forEach(
    (b) =>
      (b.onclick = () =>
        update("removeSource", { id: s.sources[+b.dataset.removeSource].id })),
  );
  if ($("#add-category"))
    $("#add-category").onsubmit = async (e) => {
      e.preventDefault();
      const name = $("#category-name").value.trim();
      try {
        const rule = await api("generateRule", { name });
        await update("categories", {
          categories: [
            ...s.categories,
            {
              id: name === "其他" ? "其他" : crypto.randomUUID(),
              name,
              rule: name === "其他" ? { ...rule, enabled: false } : rule,
            },
          ],
        });
      } catch (err) {
        errorIn(err);
      }
    };
  if ($("#category-query"))
    $("#category-query").oninput = (e) => {
      $("#category-list").innerHTML = categoryList(e.target.value);
      categoryEvents();
    };
  categoryEvents();
  if ($("#copy-prompt"))
    $("#copy-prompt").onclick = async () => {
      try {
        await api("copyPrompt");
        $("#copy-status").textContent = "已复制";
      } catch (e) {
        errorIn(e);
      }
    };
  if ($("#import-rules"))
    $("#import-rules").onclick = async () => {
      try {
        apply(await api("importRules"));
        drawSettings();
        $("#import-status").textContent = "录入成功";
      } catch (e) {
        $("#import-status").textContent = e.message;
      }
    };
  if ($("#guides")) $("#guides").onclick = () => guides();
  for (const id of ["folder-format", "document-format", "date-source"])
    if ($("#" + id))
      $("#" + id).onchange = () =>
        update("namingRules", {
          folder: $("#folder-format").value,
          document: $("#document-format").value,
          dateSource: $("#date-source").value,
        });
  $$("[data-undo]").forEach(
    (b) => (b.onclick = () => update("undo", { id: b.dataset.undo })),
  );
  const updateButton = $("#check-update"), updateStatus = $("#update-status");
  updateStatus.setAttribute("role", "status");
  let updateAvailable = false, automaticUpdate = false, restarting = false;
  updateButton.onclick = async () => {
    const b = updateButton;
    b.disabled = true;
    b.textContent = updateAvailable ? "正在准备更新…" : "正在检查…";
    try {
      if (updateAvailable) {
        const result = await api("downloadUpdate");
        updateStatus.textContent = result?.message || "已打开 Windows 下载链接。";
        restarting = Boolean(result?.automatic);
      } else {
        const r = await api("checkUpdate");
        updateStatus.textContent = r.message;
        updateAvailable = r.status === "available";
        automaticUpdate = Boolean(r.automatic);
      }
    } catch (e) {
      updateStatus.textContent = e.message;
    } finally {
      b.textContent = restarting ? "正在安装…" : updateAvailable ? automaticUpdate ? "更新并重启" : "下载更新" : "检查更新";
      b.disabled = restarting;
    }
  };
}
function categoryList(q) {
  return (
    data.settings.categories
      .filter((c) => match(c.name, q))
      .map(
        (c) =>
          `<div class="setting-row"><span class="label">${esc(c.name)}<small>${esc(c.rule?.keywords.slice(0, 4).join("、") || "接收未匹配的条目")}</small></span><button data-rule="${esc(c.id)}">规则</button><button data-rename-category="${esc(c.id)}">更改名称</button><button data-delete-category="${esc(c.id)}" ${data.settings.categories.length <= 1 ? "disabled" : ""}>删除</button></div>`,
      )
      .join("")
  );
}
function categoryEvents() {
  const save = async (cats) => {
    try {
      apply(await api("categories", { categories: cats }));
      drawSettings();
    } catch (e) {
      errorIn(e);
    }
  };
  $$("[data-delete-category]").forEach(
    (b) =>
      (b.onclick = () => {
        const target = data.settings.categories.find((c) => c.id === b.dataset.deleteCategory);
        modal(`<div class="dialog-body confirm-dialog"><h2>删除分类？</h2><p>删除「${esc(target.name)}」后，源文件和文件夹保留；未匹配的条目显示在「其他」。</p>${actions("删除分类")}</div>`);
        $("[data-cancel]").onclick = drawSettings;
        $("#confirm").onclick = () => save(data.settings.categories.filter((c) => c.id !== target.id));
      }),
  );
  $$("[data-rename-category]").forEach(
    (b) =>
      (b.onclick = () => {
        const c = data.settings.categories.find(
          (c) => c.id === b.dataset.renameCategory,
        );
        const form = $("#add-category"), input = $("#category-name");
        input.value = c.name;
        input.placeholder = "新的分类名称";
        form.innerHTML = `<input id="category-name" placeholder="新的分类名称" aria-label="分类名称" maxlength="40" required><button type="button" id="cancel-category-edit">取消</button><button class="primary">保存更名</button>`;
        $("#category-name").value = c.name;
        $("#category-name").focus();
        $("#cancel-category-edit").onclick = drawSettings;
        form.onsubmit = (event) => { event.preventDefault(); save(data.settings.categories.map((x) => x.id === c.id ? { ...x, name: $("#category-name").value.trim() } : x)); };
      }),
  );
  $$("[data-rule]").forEach(
    (b) =>
      (b.onclick = () =>
        ruleDialog(
          data.settings.categories.find((c) => c.id === b.dataset.rule),
        )),
  );
}
function ruleDialog(c) {
  let r = c.rule;
  modal(
    `<div class="dialog-body rule-dialog"><div class="rule-heading"><div><h2>「${esc(c.name)}」的分类规则</h2><span class="muted">${r.origin === "automatic" ? "系统根据分类名称自动生成" : "使用当前分类规则"}</span></div><button id="regenerate">按名称重新生成</button></div><label class="rule-toggle"><input id="rule-enabled" type="checkbox" ${r.enabled ? "checked" : ""}> 自动归入此分类</label><div class="rule-fields scroll"><label for="rule-keywords">匹配关键词</label><textarea id="rule-keywords">${esc(r.keywords.join("、"))}</textarea><small class="muted">文件名含任一关键词，或扩展名匹配时自动分类；用逗号、顿号或换行分隔。</small><label for="rule-excluded">排除关键词</label><textarea id="rule-excluded" placeholder="例如：模板、草稿（可留空）">${esc(r.excludedKeywords.join("、"))}</textarea><small class="muted">文件名命中排除词时，不会自动归入此分类。</small><label for="rule-extensions">匹配扩展名</label><input id="rule-extensions" placeholder="例如：pdf、docx（可留空）" value="${esc(r.extensions.join("、"))}"><div class="rule-options"><label>应用范围 <select id="rule-scope">${["文件和文件夹", "仅文件", "仅文件夹"].map((v) => `<option ${r.scope === v ? "selected" : ""}>${v}</option>`).join("")}</select></label><label>优先级 <select id="rule-priority"><option value="0">普通</option><option value="1" ${r.priority === 1 ? "selected" : ""}>优先</option></select></label></div><small class="muted">手动指定的分类优先保留。自动规则先比较优先级，再比较名称匹配。</small></div>${actions("保存规则")}</div>`,
  );
  $("[data-cancel]").onclick = drawSettings;
  $("#regenerate").onclick = async () => {
    try {
      ruleDialog({ ...c, rule: await api("generateRule", { name: c.name }) });
    } catch (e) {
      errorIn(e);
    }
  };
  $("#confirm").onclick = async () => {
    let terms = (s) => [
      ...new Set(
        s
          .split(/[,，、;；\n]/)
          .map((x) => x.trim())
          .filter(Boolean),
      ),
    ];
    let rule = {
      ...r,
      keywords: terms($("#rule-keywords").value),
      excludedKeywords: terms($("#rule-excluded").value),
      extensions: terms($("#rule-extensions").value).map((x) =>
        x.replace(/^\./, "").toLowerCase(),
      ),
      scope: $("#rule-scope").value,
      priority: +$("#rule-priority").value,
      enabled: $("#rule-enabled").checked,
      origin: "edited",
    };
    try {
      apply(
        await api("categories", {
          categories: data.settings.categories.map((x) =>
            x.id === c.id ? { ...x, rule } : x,
          ),
        }),
      );
      drawSettings();
    } catch (e) {
      errorIn(e);
    }
  };
}
function guides() {
  modal(
    '<div class="dialog-body guide-dialog"><div class="guide-header"><h2>操作图解</h2><button id="back-settings">关闭</button></div><div class="scroll guide-scenes"><section><h3>1　复制提示词</h3><img class="guide-image" src="../assets/copy-prompt.png" alt="复制提示词操作示意图"></section><section><h3>2　豆包发文</h3><img class="guide-image" src="../assets/doubao-message.png" alt="豆包发文操作示意图"></section><section><h3>3　录入规则</h3><img class="guide-image" src="../assets/import-rules.png" alt="录入规则操作示意图"></section></div></div>',
  );
  $("#back-settings").onclick = drawSettings;
}
$("#files").ondragstart = (e) => {
  const row = e.target.closest("[data-file]");
  if (!row) return;
  const item = fileRows.find((x) => x.path === row.dataset.file);
  if (!item) return;
  focusPane("files");
  dragItems = selected.has(item.path) ? selectedItems() : [item];
  e.dataTransfer.setData(
    "application/x-guiyu",
    JSON.stringify(dragItems.map((e) => e.path)),
  );
  e.dataTransfer.effectAllowed = "move";
};
$("#files").ondragover = (e) => {
  const target = e.target.closest("[data-group], [data-file]");
  if (!dragItems.length || mode !== "按类别" || !target) return;
  e.preventDefault();
  target.classList.add("drop-target");
};
$("#files").ondragleave = (e) =>
  e.target.closest(".drop-target")?.classList.remove("drop-target");
$("#files").ondrop = (e) => {
  e.preventDefault();
  const target = e.target.closest("[data-group],[data-file]");
  if (!target || !dragItems.length) return;
  let id =
    target.dataset.group ||
    category(fileRows.find((x) => x.path === target.dataset.file));
  if (!data.settings.categories.some((c) => c.id === id)) return;
  const items = dragItems;
  dragItems = [];
  action(async () => apply(await api("assign", { items, id })));
};
$("#files").ondragend = () => {
  dragItems = [];
  render();
};
$("#directories").ondragstart = (e) => {
  if (working) { e.preventDefault(); return; }
  const button = e.target.closest("[data-order-path]");
  if (!button) return;
  dragDir = { path: button.dataset.orderPath, root: button.dataset.orderRoot, kind: button.dataset.orderKind };
  e.dataTransfer.effectAllowed = "move";
  e.dataTransfer.setData("application/x-guiyu-dir", JSON.stringify(dragDir));
};
function clearRailDrop() {
  $$("#directories .insert-before, #directories .insert-after").forEach(el => el.classList.remove("insert-before", "insert-after"));
}
function railDrop(e) {
  if (!dragDir) return null;
  const group = e.target.closest("[data-root-group]");
  if (!group || (dragDir.kind === "entry" && group.dataset.rootGroup !== dragDir.root)) return null;
  if (dragDir.kind === "root") {
    if (group.dataset.rootGroup === dragDir.path) return null;
    const bounds = group.getBoundingClientRect();
    return { element: group, path: group.dataset.rootGroup, after: e.clientY >= bounds.top + bounds.height / 2 };
  }
  const choices = [...group.querySelectorAll('[data-order-kind="entry"]')];
  // Nearest-row hit testing includes the visual gaps and space after the last row.
  const button = choices.find(el => e.clientY < el.getBoundingClientRect().bottom) || choices.at(-1);
  if (!button || button.dataset.orderPath === dragDir.path) return null;
  const bounds = button.getBoundingClientRect();
  return { element: button, path: button.dataset.orderPath, after: e.clientY >= bounds.top + bounds.height / 2 };
}
$("#directories").ondragover = (e) => {
  clearRailDrop();
  const target = railDrop(e);
  if (!target) return;
  e.preventDefault(); e.dataTransfer.dropEffect = "move";
  target.element.classList.add(target.after ? "insert-after" : "insert-before");
};
$("#directories").ondrop = (e) => {
  e.preventDefault();
  const target = railDrop(e), from = dragDir;
  clearRailDrop();
  dragDir = null;
  if (!target || !from) return;
  const before = from.kind === "root" ? data.settings.roots : data.snapshot.rootEntries.filter(e => e.directory === from.root).map(e => e.path);
  const paths = window.GuiyuRailOrder.moved(before, from.path, target.path, target.after);
  if (!paths || paths.every((p, i) => p === before[i])) return;
  action(async () => apply(await api(from.kind === "root" ? "orderRoots" : "order", { root: from.root, paths })));
};
$("#directories").ondragleave = e => { if (!e.currentTarget.contains(e.relatedTarget)) clearRailDrop(); };
$("#directories").ondragend = () => { dragDir = null; clearRailDrop(); };
function dragDivider(el, type) {
  el.addEventListener("pointerdown", (e) => {
    el.setPointerCapture(e.pointerId);
    const startX = e.clientX,
      startY = e.clientY,
      old = [
        parseFloat(
          getComputedStyle(document.documentElement).getPropertyValue("--left"),
        ),
        parseFloat(
          getComputedStyle(document.documentElement).getPropertyValue(
            "--middle",
          ),
        ),
      ],
      fraction = data.settings.sidebarFraction;
    function move(ev) {
      if (type === "rail") {
        const total = $("#rail-sections").clientHeight;
        data.settings.sidebarFraction = Math.max(
          0.2,
          Math.min(0.85, fraction + (ev.clientY - startY) / total),
        );
        $("#directory-section").style.height =
          data.settings.sidebarFraction * 100 + "%";
      } else {
        let index = type === "left" ? 0 : 1;
        old[index] = Math.max(
          index ? 260 : 200,
          Math.min(
            index ? 700 : 400,
            (index === 0 ? data.settings.widths[0] : data.settings.widths[1]) +
              ev.clientX -
              startX,
          ),
        );
        document.documentElement.style.setProperty(
          index ? "--middle" : "--left",
          old[index] + "px",
        );
      }
    }
    function up() {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      if (type !== "rail") data.settings.widths = old;
      api("layout", {
        fraction: data.settings.sidebarFraction,
        widths: data.settings.widths,
      }).catch((e) => toast(e.message, true));
    }
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up, { once: true });
  });
  el.onkeydown = (e) => {
    let vertical = type === "rail";
    if (
      !(
        vertical ? ["ArrowUp", "ArrowDown"] : ["ArrowLeft", "ArrowRight"]
      ).includes(e.key)
    )
      return;
    e.preventDefault();
    let delta = e.key === "ArrowUp" || e.key === "ArrowLeft" ? -1 : 1;
    if (vertical)
      data.settings.sidebarFraction = Math.max(
        0.2,
        Math.min(0.85, data.settings.sidebarFraction + 0.03 * delta),
      );
    else {
      let i = type === "left" ? 0 : 1;
      data.settings.widths[i] = Math.max(
        i ? 260 : 200,
        Math.min(i ? 700 : 400, data.settings.widths[i] + 10 * delta),
      );
    }
    api("layout", {
      fraction: data.settings.sidebarFraction,
      widths: data.settings.widths,
    }).catch((e) => toast(e.message, true));
    apply(data);
  };
}
dragDivider($("#rail-divider"), "rail");
dragDivider($("#left-divider"), "left");
dragDivider($("#right-divider"), "right");
document.addEventListener("keydown", (e) => {
  if ($("#modal").open || e.target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))
    return;
  if (e.key === "Escape") {
    selected.clear();
    $("#context").hidden = true;
    render();
    return;
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "f") {
    e.preventDefault();
    $("#query").focus();
    return;
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "r") {
    e.preventDefault();
    action(refresh);
    return;
  }
  if (e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "v") {
    e.preventDefault(); pasteSelection(); return;
  }
  if (operationPane === "directories" && e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "c") {
    e.preventDefault(); copySelection([{ path: railFile || dir }]); return;
  }
  if (
    !["projects", "files"].includes(document.activeElement?.id) &&
    !e.target.closest(".file-row,.project-row")
  )
    return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "a") {
    e.preventDefault();
    selected = new Set(visibleRows.map((e) => e.path));
    if (selectionPane === "projects") showMiddleFolder(selectedItems().at(-1));
    else render();
    return;
  }
  let items = selectedItems();
  if (e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "c" && items.length) {
    e.preventDefault();
    copySelection(items);
  } else if (e.key === " " && items.length) {
    e.preventDefault();
    action(() => api("preview", { path: items[0].path }));
  } else if (e.key === "F2" && items.length) {
    e.preventDefault();
    namingDialog(items, false);
  } else if (e.key === "Enter" && items.length) {
    e.preventDefault();
    if (items[0].folder && selectionPane === "projects") openMiddleFolder(items[0]);
    else if (items[0].folder) openFileItem(items[0]);
    else action(() => api("open", { path: items[0].path }));
  } else if (e.key === "Delete" && items.length) {
    e.preventDefault();
    action(async () => {
      apply(await api("trash", { items }));
      await load();
    });
  } else if (["ArrowUp", "ArrowDown"].includes(e.key) && visibleRows.length) {
    e.preventDefault();
    let i = visibleRows.findIndex((x) => selected.has(x.path));
    i = Math.max(
      0,
      Math.min(visibleRows.length - 1, i + (e.key === "ArrowUp" ? -1 : 1)),
    );
    if (selectionPane === "projects") selectMiddle(visibleRows[i], e);
    else select(visibleRows[i], e);
    document
      .querySelector(
        `[data-file="${CSS.escape(visibleRows[i].path)}"], [data-project="${CSS.escape(visibleRows[i].path)}"]`,
      )
      ?.scrollIntoView({ block: "nearest" });
  }
});
window.guiyu?.onCommand?.((command) => {
  api("consumeCommand");
  command.type === "--smart-name"
    ? namingDialog(command.items, true)
    : archiveDialog(command.items);
});
window.guiyu?.onUpdateProgress?.(value => {
  const status = $("#update-status");
  if (status) status.textContent = value.phase === "downloading" ? `正在下载更新 ${value.percent}%` : value.phase === "verifying" ? "正在校验更新包…" : "正在安装，完成后自动重新打开…";
});
api("state")
  .then((d) => {
    apply(d);
    if (d.pendingCommand) {
      const c = d.pendingCommand;
      api("consumeCommand");
      c.type === "--smart-name"
        ? namingDialog(c.items, true)
        : archiveDialog(c.items);
    }
  })
  .catch((e) => toast(e.message, true));

$("#modal").addEventListener("close",()=>window.guiyu?.cancelNaming?.());
