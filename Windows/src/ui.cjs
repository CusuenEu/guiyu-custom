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
const icon = (e) =>
  e.folder
    ? folder
    : `<span aria-hidden="true" class="doc-icon ${/\.docx?$/i.test(e.name) ? "word" : /\.xlsx?$/i.test(e.name) ? "excel" : /\.pdf$/i.test(e.name) ? "pdf" : ""}">${/\.docx?$/i.test(e.name) ? "W" : /\.xlsx?$/i.test(e.name) ? "X" : /\.pdf$/i.test(e.name) ? "⌁" : "≡"}</span>`;
let data,
  dir = "",
  project = null,
  source = null,
  sourceFolder = null,
  sourceChildren = [],
  sourceLoading = false,
  sourceFocus = "projects",
  sourceGeneration = 0,
  sourceLoad = Promise.resolve(),
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
  data = d;
  const w = data.settings.widths || [240, 390];
  document.documentElement.style.setProperty("--left", w[0] + "px");
  document.documentElement.style.setProperty("--middle", w[1] + "px");
  $("#directory-section").style.height =
    data.settings.sidebarFraction * 100 + "%";
  if (!data.snapshot.directories.some((d) => d.path === dir)) {
    dir = data.snapshot.directories[0]?.path || "";
    project = null;
    if (!source) current = "";
  }
  if (project && !data.snapshot.projects.some((p) => p.path === project.path)) {
    project = null;
    current = "";
  }
  rail();
  render();
}
function rail() {
  let roots = data.settings.roots,
    dirs = data.snapshot.directories;
  $("#directories").innerHTML =
    roots
      .map(
        (root) =>
          (roots.length > 1
            ? `<div class="root-label" title="${esc(root)}">${esc(basename(root))}</div>`
            : "") +
          dirs
            .filter((d) => d.root === root)
            .map(
              (d) =>
                `<button data-dir="${esc(d.path)}" draggable="true" class="${!source && dir === d.path ? "active" : ""}" title="${esc(d.path)}">${folder}<span>${esc(d.name)}</span></button>`,
            )
            .join(""),
      )
      .join("") || '<div class="root-label">关联项目总目录开始使用</div>';
  $("#sources").innerHTML = data.settings.sources
    .map(
      (s) =>
        `<button data-source="${esc(s.id)}" class="${source?.id === s.id ? "active" : ""}" title="${esc(s.path || "Windows 最近访问的文件")}"><span aria-hidden="true" style="font-size:23px">${s.kind === "recent" ? "◷" : "⇩"}</span><span>${esc(s.name)}</span></button>`,
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
let visibleRows = [];
function render() {
  if (!data) return;
  let projects = source
    ? rows
    : data.snapshot.projects.filter((p) => p.directory === dir);
  if (query)
    projects = projects.filter(
      (p) =>
        match(p.name, query) ||
        (!source &&
          data.snapshot.files.some(
            (e) => e.project === p.path && match(e.name, query),
          )),
    );
  projects = [...projects].sort(
    (a, b) => (query ? relevance(a) - relevance(b) : 0) || order(a, b),
  );
  const projectMarkup =
    projects
      .map(
        (e) =>
          `<div role="option" tabindex="-1" aria-selected="${source ? (sourceFocus === "projects" && selected.has(e.path)) || sourceFolder?.path === e.path : project?.path === e.path}" class="project-row ${source ? ((sourceFocus === "projects" && selected.has(e.path)) || sourceFolder?.path === e.path ? "selected" : "") : project?.path === e.path ? "selected" : ""}" data-project="${esc(e.path)}" title="${esc(e.name)}">${icon(e)}<span class="name">${esc(e.name)}</span></div>`,
      )
      .join("") ||
    `<div class="empty">${folder}<span>${!data.settings.roots.length && !source ? "在设置中选择项目总目录，开始浏览" : "当前目录没有匹配的项目或文件"}</span>${!data.settings.roots.length && !source ? '<button id="empty-settings">打开设置</button><button id="demo">体验示例空间</button>' : ""}</div>`;
  const existingProjects = [...$("#projects").querySelectorAll("[data-project]")];
  if (projects.length && existingProjects.length === projects.length && existingProjects.every((el, i) => el.dataset.project === projects[i].path && el.title === projects[i].name)) {
    existingProjects.forEach((el, i) => {
      const active = source ? (sourceFocus === "projects" && selected.has(projects[i].path)) || sourceFolder?.path === projects[i].path : project?.path === projects[i].path;
      el.classList.toggle("selected", active);
      el.setAttribute("aria-selected", String(active));
    });
  } else $("#projects").innerHTML = projectMarkup;
  $("#subnav").innerHTML = "";
  let files = [];
  if (source && sourceFolder) {
    files = [...sourceChildren].sort((a, b) => Number(b.folder) - Number(a.folder) || a.name.localeCompare(b.name, "zh"));
    sourceChildren = files;
    if (current !== sourceFolder.path)
      $("#subnav").innerHTML = '<button id="up" aria-label="上一级">‹</button><span title="' + esc(current) + '">' + esc(basename(current)) + '</span>';
  } else if (query && !source) {
    files = data.snapshot.files.filter(
      (e) => e.directory === dir && match(e.name, query),
    );
    $("#subnav").textContent =
      "搜索结果 · 全部项目" +
      (data.snapshot.unavailable.length ? " · 部分目录无法读取" : "");
  } else if (project && !source) {
    files = rows;
    if (current !== project.path)
      $("#subnav").innerHTML =
        '<button id="up" aria-label="上一级">‹</button><span title="' +
        esc(current) +
        '">' +
        esc(basename(current)) +
        "</span>";
  }
  visibleRows = source && sourceFocus === "projects" ? projects : files;
  let body = "";
  if (source && sourceFolder) {
    body = sourceLoading ? '<div class="empty">正在读取文件夹…</div>' : files.length ? files.map(fileRow).join("") : '<div class="empty">当前文件夹没有内容</div>';
  } else if (!data.settings.categories.length)
    body =
      '<div class="empty"><button id="empty-categories">请设置文件分类</button></div>';
  else if (source || (!project && !query)) body = "";
  else if (!files.length)
    body =
      '<div class="empty">' +
      (query ? "没有匹配的三级文件或文件夹" : "当前文件夹没有内容") +
      "</div>";
  else if (mode === "源文档") {
    body = [...files]
      .sort(
        (a, b) =>
          Number(b.folder) - Number(a.folder) ||
          a.name.localeCompare(b.name, "zh"),
      )
      .map(fileRow)
      .join("");
  } else {
    let groups = new Map();
    if (mode === "按类别") {
      for (const c of data.settings.categories)
        groups.set(c.id, { name: c.name, items: [] });
      for (const e of files) {
        let c = category(e);
        if (groups.has(c)) groups.get(c).items.push(e);
      }
      for (const [id, g] of groups)
        if (g.items.length)
          body +=
            groupHeader(id, g.name, g.items.length) +
            (collapsed.has(id) ? "" : g.items.map(fileRow).join(""));
    } else {
      for (const e of [...files].sort((a, b) => b.mtime - a.mtime)) {
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
  $("#count").textContent =
    (source && sourceFolder) || (!source && (project || query)) ? `${files.length} 个项目` : "";
  $("#selected-count").textContent = `已选 ${selected.size} 项`;
  $("#batch-tools").hidden = (source && sourceFocus === "projects") || selected.size < 2;
  $$("[data-mode]").forEach((b) =>
    b.setAttribute("aria-selected", b.dataset.mode === mode),
  );
}
function term(n, t) {
  t = norm(t);
  if (/^[\x20-\x7f]+$/.test(t))
    return new RegExp(
      "(^|[^a-z0-9])" +
        t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
        "($|[^a-z0-9])",
    ).test(norm(n));
  return norm(n).includes(t);
}
function category(e) {
  let s = data.settings,
    a = s.assignments[e.path];
  if (
    a?.identity === e.identity &&
    s.categories.some((c) => c.id === a.categoryID)
  )
    return a.categoryID;
  let scores = s.categories.map((c) => {
    let r = c.rule;
    if (
      !r?.enabled ||
      (r.scope === "仅文件" && e.folder) ||
      (r.scope === "仅文件夹" && !e.folder) ||
      r.excludedKeywords.some((t) => term(e.name, t))
    )
      return [c.id, -1];
    let hits = r.keywords.filter((t) => term(e.name, t));
    return [
      c.id,
      hits.length
        ? r.priority * 1000 +
          200 +
          Math.min(80, Math.max(...hits.map((t) => t.length)))
        : !e.folder &&
            r.extensions.some((x) => norm(e.name).endsWith("." + norm(x)))
          ? r.priority * 1000 + 20
          : -1,
    ];
  });
  let max = Math.max(-1, ...scores.map((x) => x[1])),
    wins = scores.filter((x) => x[1] === max);
  return max >= 0 && wins.length === 1
    ? wins[0][0]
    : (
        s.categories.find((c) => c.id === "其他" || c.name === "其他") ||
        s.categories[0]
      )?.id;
}
function groupHeader(id, name, count) {
  return `<div role="button" tabindex="0" aria-expanded="${!collapsed.has(id)}" class="category-header" data-group="${esc(id)}"><span class="chevron" aria-hidden="true"></span><span>${esc(name)}</span><small>${count}</small></div>`;
}
function fileRow(e) {
  return `<div role="option" aria-selected="${selected.has(e.path)}" class="file-row ${selected.has(e.path) ? "selected" : ""}" data-file="${esc(e.path)}" draggable="true" title="${esc(e.name)}">${icon(e)}<div class="name-wrap"><div class="name">${esc(e.name)}</div>${query ? `<small>${esc(e.projectName)}</small>` : ""}</div><span class="date">${esc(new Intl.DateTimeFormat("sv-SE", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(e.mtime))}</span></div>`;
}
async function load() {
  const gen = ++generation;
  let next = [];
  if (source) next = await api("source", { id: source.id });
  else if (current) next = await api("list", { path: current });
  if (gen !== generation) return;
  rows = next;
  if (source && sourceFolder) {
    try { sourceChildren = await api("list", { path: current }); }
    catch (e) { sourceFolder = null; current = ""; sourceChildren = []; toast(e.message, true); }
  }
  if (gen !== generation) return;
  selected.clear();
  render();
}
async function refresh() {
  let p = project?.path,
    c = current;
  const d = await api("refresh");
  apply(d);
  project = d.snapshot.projects.find((e) => e.path === p) || null;
  current = project || (source && sourceFolder) ? c : "";
  await load();
}
function selectedItems() {
  return visibleRows.filter((e) => selected.has(e.path));
}
function select(e, event) {
  let index = visibleRows.findIndex((x) => x.path === e.path);
  if (event.shiftKey && anchor !== null) {
    let start = Math.min(anchor, index),
      end = Math.max(anchor, index);
    if (!event.ctrlKey) selected.clear();
    for (const x of visibleRows.slice(start, end + 1)) selected.add(x.path);
  } else if (event.ctrlKey || event.metaKey) {
    if (selected.has(e.path)) selected.delete(e.path);
    else selected.add(e.path);
    anchor = index;
  } else {
    selected = new Set([e.path]);
    anchor = index;
  }
  for (const el of $$('[data-file], [data-project]')) {
    const path = el.dataset.file || el.dataset.project;
    if (el.dataset.project && (!source || sourceFocus !== "projects")) continue;
    if (el.dataset.file && source && sourceFocus !== "files") continue;
    const active = selected.has(path);
    el.classList.toggle("selected", active);
    el.setAttribute("aria-selected", String(active));
  }
  $("#selected-count").textContent = `已选 ${selected.size} 项`;
  $("#batch-tools").hidden = (source && sourceFocus === "projects") || selected.size < 2;
}
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
$("#directories").onclick = (e) => {
  const b = e.target.closest("[data-dir]");
  if (!b) return;
  dir = b.dataset.dir;
  source = null;
  sourceFolder = null; sourceChildren = []; sourceLoading = false; sourceGeneration++;
  project = null;
  current = "";
  rows = [];
  selected.clear();
  rail();
  render();
};
$("#sources").onclick = (e) => {
  const b = e.target.closest("[data-source]");
  if (!b) return;
  action(async () => {
    source = data.settings.sources.find((s) => s.id === b.dataset.source);
    sourceFolder = null; sourceChildren = []; sourceLoading = false; sourceFocus = "projects"; sourceGeneration++;
    project = null;
    current = "";
    rail();
    await sourceLoad;
    await load();
  });
};
$("#projects").onclick = (e) => {
  const b = e.target.closest("[data-project]");
  if (!b) {
    if (e.target.id === "empty-settings") settings();
    if (e.target.id === "demo") action(async () => apply(await api("demo")));
    return;
  }
  const item = (source ? rows : data.snapshot.projects).find(
    (x) => x.path === b.dataset.project,
  );
  if (source) {
    if (sourceFocus !== "projects") { selected.clear(); sourceFocus = "projects"; }
    visibleRows = [...rows].filter((x) => !query || match(x.name, query)).sort((a, b) => (query ? relevance(a) - relevance(b) : 0) || order(a, b));
    select(item, e);
    if (!e.ctrlKey && !e.metaKey && !e.shiftKey) {
      if (e.detail > 1) return;
      const gen = ++sourceGeneration;
      sourceFolder = item.folder ? item : null;
      sourceChildren = []; current = item.folder ? item.path : "";
      sourceLoading = item.folder;
      render();
      if (item.folder) sourceLoad = sourceLoad.then(async () => {
        if (gen !== sourceGeneration) return;
        const children = await api("list", { path: item.path });
        if (gen !== sourceGeneration) return;
        sourceChildren = children; sourceLoading = false; render();
      }).catch((err) => { if (gen === sourceGeneration) { sourceFolder = null; sourceLoading = false; current = ""; render(); toast(err.message, true); } });
    }
  }
  else if (item.folder) {
    const gen = ++generation;
      project = item;
      current = item.path;
      selected.clear();
      rows = [];
      render();
      api("list", { path: item.path }).then((next) => {
        if (gen !== generation || source || project?.path !== item.path) return;
        rows = next;
        render();
      }).catch((err) => { if (gen === generation) toast(err.message, true); });
  }
  else {
    selected = new Set([item.path]);
  }
};
$("#projects").ondblclick = (e) => {
  const p = e.target.closest("[data-project]")?.dataset.project;
  if (p) action(async () => { if (source) await sourceLoad; await api("open", { path: p }); });
};
$("#files").onclick = (e) => {
  const b = e.target.closest("[data-file]"),
    g = e.target.closest("[data-group]");
  if (b) {
    if (source && sourceFocus !== "files") { selected.clear(); sourceFocus = "files"; visibleRows = sourceChildren; }
    select(visibleRows.find((x) => x.path === b.dataset.file), e);
  }
  else if (g) {
    collapsed.has(g.dataset.group)
      ? collapsed.delete(g.dataset.group)
      : collapsed.add(g.dataset.group);
    render();
  } else if (e.target.id === "empty-categories") settings("文件分类");
};
$("#files").ondblclick = (e) => {
  const p = e.target.closest("[data-file]")?.dataset.file,
    item = visibleRows.find((x) => x.path === p);
  if (!item) return;
  action(async () => {
    if (item.folder) {
      if (source) {
        const gen = ++sourceGeneration;
        const children = await api("list", { path: item.path });
        if (gen !== sourceGeneration || !source || !sourceFolder) return;
        current = item.path;
        sourceChildren = children;
        selected.clear(); sourceFocus = "files"; render();
        return;
      }
      if (query) {
        project = data.snapshot.projects.find((p) => p.path === item.project);
        query = "";
        $("#query").value = "";
      }
      current = item.path;
      await load();
    } else await api("open", { path: p });
  });
};
$("#subnav").onclick = (e) => {
  if (e.target.id !== "up") return;
  action(async () => {
    const parent = current.replace(/[\\/][^\\/]+[\\/]?$/, "");
    if (source && sourceFolder) {
      const gen = ++sourceGeneration;
      const children = await api("list", { path: parent });
      if (gen !== sourceGeneration || !source || !sourceFolder) return;
      current = parent; sourceChildren = children; selected.clear(); sourceFocus = "files"; render();
    } else { current = parent; await load(); }
  });
};
$$("[data-mode]").forEach(
  (b) =>
    (b.onclick = () => {
      mode = b.dataset.mode;
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
        ? `<button role="menuitem" data-menu="${n}">${esc(i.label)}</button>`
        : "<hr>",
    )
    .join("");
  el.hidden = false;
  el.style.left = Math.min(event.clientX, innerWidth - 250) + "px";
  el.style.top =
    Math.min(event.clientY, innerHeight - el.offsetHeight - 8) + "px";
  el.onclick = (e) => {
    let n = e.target.closest("[data-menu]")?.dataset.menu;
    if (n === undefined) return;
    el.hidden = true;
    items[n].fn();
  };
  el.querySelector("button")?.focus();
}
function fileMenu(ev, items, archive = false) {
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
  menu(ev, actions);
}
$("#files").oncontextmenu = (e) => {
  const p = e.target.closest("[data-file]")?.dataset.file;
  if (p) {
    if (source && sourceFocus !== "files") { selected.clear(); sourceFocus = "files"; visibleRows = sourceChildren; }
    if (!selected.has(p)) selected = new Set([p]);
    render();
    fileMenu(e, selectedItems(), !!source);
  }
};
$("#projects").oncontextmenu = (e) => {
  const p = e.target.closest("[data-project]")?.dataset.project;
  if (!p) return;
  const item = (source ? rows : data.snapshot.projects).find(
    (x) => x.path === p,
  );
  if (source) {
    if (sourceFocus !== "projects") { selected.clear(); sourceFocus = "projects"; visibleRows = rows; }
    if (!selected.has(p)) selected = new Set([p]);
    render();
    fileMenu(e, selectedItems(), true);
  } else fileMenu(e, [item]);
};
$("#batch-menu").onclick = (e) => fileMenu(e, selectedItems(), !!source);
document.addEventListener("pointerdown", (e) => {
  if (!e.target.closest("#context")) $("#context").hidden = true;
});
$("#directories").oncontextmenu = (e) => {
  let d = e.target.closest("[data-dir]")?.dataset.dir;
  if (d)
    menu(e, [
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
function actions(confirm) {
  return `<div id="dialog-error" class="inline-error" role="alert"></div><div class="dialog-actions"><button data-cancel>取消</button><button id="confirm" class="primary">${confirm}</button></div>`;
}
function smartHeader(title, symbol) {
  return `<div class="smart-header"><span class="smart-header-icon" aria-hidden="true">${symbol}</span><h2>${title}</h2></div>`;
}
async function namingDialog(items, smart) {
  modal(
    `<div class="dialog-body" style="height:460px"><h2>${smart ? "智能命名" : "更改名称"}</h2><p class="muted">正在准备${items.length}个条目…</p>${actions("确认重命名")}</div>`,
  );
  $("#confirm").disabled = true;
  let suggestions;
  try {
    suggestions = smart
      ? await api("naming", { items })
      : items.map((e) => ({
          entry: e,
          ext: e.folder ? "" : e.name.match(/\.[^.]+$/)?.[0] || "",
          prefix: "",
          candidates: [],
        }));
  } catch (e) {
    errorIn(e);
    return;
  }
  if (!$("#modal").open) return;
  const batch = items.length > 1;
  let body = `<div class="dialog-body ${smart && !batch ? "smart-dialog" : batch ? "batch-dialog" : "direct-dialog"}" style="height:${batch ? 600 : 460}px">${smart && !batch ? smartHeader("智能命名", "✎") : `<h2>${batch ? "批量" : ""}${smart ? "智能命名" : "更改名称"}</h2>`}`;
  if (!batch) {
    const r = suggestions[0],
      e = r.entry;
    let stem = smart
      ? r.candidates[0]?.name || ""
      : e.name.slice(0, e.name.length - r.ext.length);
    body += `<div class="original-name"><span class="muted">原名称</span><div>${esc(e.name)}</div></div><div class="name-editor"><label for="name-stem">${smart ? "修改名称" : "新名称"}</label><div class="naming-line">${smart ? (r.format === "month" ? `<input class="month" id="name-prefix" aria-label="月份" type="number" min="1" max="12" value="${parseInt(r.prefix)}"><span>月</span>` : `<span id="fixed-prefix">${esc(r.prefix)}</span>`) : ""}<input id="name-stem" aria-label="识别的名称" value="${esc(stem)}"><span>${esc(r.ext)}</span></div></div>${smart ? `<h3>推荐名称</h3><div class="scroll candidate-list">${r.candidates.map((c, i) => `<button class="candidate ${i === 0 ? "chosen" : ""}" aria-pressed="${i === 0}" data-candidate="${i}" title="${esc(c.evidence)}"><span aria-hidden="true" class="choice-mark"></span>${esc(c.name)}</button>`).join("") || '<p class="muted">未找到推荐名称，可直接填写。</p>'}</div>` : `<p class="muted">更改后：<span id="direct-preview">${esc(stem + r.ext)}</span></p><p class="muted">确认后同步更改本机名称，保留扩展名，同名不覆盖。</p>`}${r.warnings?.length ? '<div class="muted">部分文档未能提取，您可以手工填写；详情见提示。<span title="' + esc(r.warnings.join("\n")) + '">ⓘ</span></div>' : ""}`;
  } else {
    body += `<p class="muted batch-description">逐项核对并修改新名称；取消勾选可跳过。确认后同步更改本机名称，同名不覆盖。 <span id="batch-count">${suggestions.length} / ${suggestions.length} 项</span></p>`;
    if (!smart)
      body +=
        '<div class="setting-form"><input id="find" placeholder="查找文字" aria-label="查找文字"><input id="replace" placeholder="替换为" aria-label="替换为"><input id="prefix" placeholder="添加前缀" aria-label="添加前缀"><button id="apply-batch">应用</button></div>';
    body +=
      '<div class="scroll">' +
      suggestions
        .map(
          (r, i) =>
            `<div class="batch-original">${esc(r.entry.name)}</div><div class="batch-row"><input type="checkbox" data-include="${i}" aria-label="处理 ${esc(r.entry.name)}" checked><input type="text" data-name="${i}" aria-label="新名称 ${esc(r.entry.name)}" value="${esc(smart ? r.prefix + " " + (r.candidates[0]?.name || "") : r.entry.name.slice(0, r.entry.name.length - r.ext.length))}"><span>${esc(r.ext)}</span>${smart ? `<select data-alternate="${i}" aria-label="其他候选"><option value="">其他候选</option>${r.candidates.map((c, j) => `<option value="${j}">${esc(c.name)}</option>`).join("")}</select>` : ""}</div>`,
        )
        .join("") +
      "</div>";
  }
  body += actions("确认重命名") + "</div>";
  modal(body);
  $$("[data-candidate]").forEach(
    (b) =>
      (b.onclick = () => {
        $("#name-stem").value = suggestions[0].candidates[+b.dataset.candidate].name;
        $$('[data-candidate]').forEach((item) => { const chosen = item === b; item.classList.toggle('chosen', chosen); item.setAttribute('aria-pressed', String(chosen)); });
      }),
  );
  if (!batch && !smart) $("#name-stem").oninput = (e) => { $("#direct-preview").textContent = e.target.value + suggestions[0].ext; };
  if (!batch && smart) $("#name-stem").oninput = (e) => { $$('[data-candidate]').forEach((item) => { const chosen = suggestions[0].candidates[+item.dataset.candidate].name === e.target.value; item.classList.toggle('chosen', chosen); item.setAttribute('aria-pressed', String(chosen)); }); };
  if (batch) $$('[data-include]').forEach((b) => b.onchange = () => { $("#batch-count").textContent = `${$$('[data-include]:checked').length} / ${suggestions.length} 项`; });
  $$("[data-alternate]").forEach(
    (b) =>
      (b.onchange = () => {
        if (b.value !== "") {
          let i = +b.dataset.alternate;
          $(`[data-name="${i}"]`).value =
            suggestions[i].prefix +
            " " +
            suggestions[i].candidates[+b.value].name;
        }
      }),
  );
  if ($("#apply-batch"))
    $("#apply-batch").onclick = () =>
      suggestions.forEach((r, i) => {
        if (!$(`[data-include="${i}"]`).checked) return;
        let stem = r.entry.name.slice(0, r.entry.name.length - r.ext.length),
          find = $("#find").value;
        if (find) stem = stem.split(find).join($("#replace").value);
        $(`[data-name="${i}"]`).value = $("#prefix").value + stem;
      });
  $("#confirm").onclick = async () => {
    const b = $("#confirm");
    b.disabled = true;
    try {
      let plans = suggestions
        .map((r, i) => {
          let stem = batch
            ? $(`[data-name="${i}"]`).value
            : $("#name-stem").value;
          if (!batch && smart) {
            let prefix =
              r.format === "month" ? $("#name-prefix").value + "月" : r.prefix;
            stem = prefix + " " + stem;
          }
          return {
            entry: r.entry,
            name: stem.trim() + r.ext,
            include: batch ? $(`[data-include="${i}"]`).checked : true,
          };
        })
        .filter((x) => x.include);
      if (smart)
        for (const p of plans) {
          const r = suggestions.find((r) => r.entry.path === p.entry.path);
          let m = p.name.match(/^(\d+)月\s/);
          if (r.format === "month" && (!m || +m[1] < 1 || +m[1] > 12))
            throw Error("月份必须为1至12月。");
          if (r.format === "monthDay") {
            let m = p.name.match(/^(\d{2})(\d{2})\s/),
              date = m ? new Date(2024, +m[1] - 1, +m[2]) : null;
            if (!m || date.getMonth() !== +m[1] - 1 || date.getDate() !== +m[2])
              throw Error("请保留有效的四位MMDD前缀。");
          }
          if (r.format === "category" && !p.name.startsWith(r.prefix + " "))
            throw Error("请保留当前分类前缀。");
        }
      const result = await api("rename", { plans });
      $("#modal").close();
      for (const p of plans) {
        if (p.entry.folder) {
          const target =
            p.entry.path.slice(0, p.entry.path.length - p.entry.name.length) +
            p.name;
          if (project?.path === p.entry.path)
            project =
              result.snapshot.projects.find((x) => x.path === target) || null;
          if (
            current === p.entry.path ||
            current.startsWith(p.entry.path + "\\") ||
            current.startsWith(p.entry.path + "/")
          )
            current = target + current.slice(p.entry.path.length);
        }
      }
      apply(result);
      await load();
      toast(`已重命名 ${result.result} 项`);
    } catch (e) {
      errorIn(e);
      if (/已完成/.test(e.message)) b.dataset.partial = "true";
    } finally {
      if (b.dataset.partial !== "true") b.disabled = false;
    }
  };
}
async function archiveDialog(items) {
  modal(
    `<div class="dialog-body smart-dialog archive-dialog" style="height:620px">${smartHeader("智能归档", "⇩")}<div class="file-summary"><span class="summary-icon" aria-hidden="true">▤</span><span>${esc(items[0]?.name || "")}${items.length > 1 ? ` 等 ${items.length} 项` : ""}<small>${items.length} 项待归档</small></span></div><input id="archive-query" placeholder="搜索项目名、单位词或关键词" aria-label="搜索归档项目"><div class="scroll" id="archive-projects">正在查找推荐项目…</div>${actions("确认归档")}</div>`,
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
    const filtered = results.projects.filter((p) => match(p.name, q));
    $("#archive-projects").innerHTML =
      filtered
        .map(
          (p, i) =>
            `${i === 0 ? `<h3>${q ? "搜索结果" : p.score > 0 ? "匹配项目" : "全部项目"}</h3>` : !q && p.score === 0 && filtered[i - 1]?.score > 0 ? "<h3>其他项目</h3>" : ""}<button class="archive-choice" aria-pressed="false" data-target="${esc(p.path)}" title="${esc(p.evidence)}">${folder}<span class="name-wrap"><span class="name">${esc(p.name)}</span><small>${esc(basename(p.directory))}</small></span><span class="choice-mark" aria-hidden="true"></span></button>`,
        )
        .join("") || '<p class="muted">没有匹配的项目</p>';
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
    content = `<h3>项目总目录 <button id="settings-add-root">关联目录…</button></h3>${s.roots.map((r, i) => `<div class="setting-row">${folder}<span class="label">${esc(basename(r))}<small title="${esc(r)}">${esc(r)}</small></span><button data-remove-root="${i}" aria-label="移除关联 ${esc(basename(r))}">−</button></div>`).join("") || '<p class="muted">关联一个或多个项目总目录，开始浏览。</p>'}<p class="muted">左侧展示各总目录下的子文件夹。移除关联会保留原文件。</p><h3>可归档目录 <button id="settings-add-source">关联文件夹…</button></h3>${s.sources.map((r, i) => `<div class="setting-row"><span class="label">${esc(r.name)}<small>${esc(r.path || "Windows 最近访问的文件")}</small></span><button data-remove-source="${i}">移除关联</button></div>`).join("")}<p><button id="restore-sources">恢复默认入口</button></p><h3>资源管理器快捷入口</h3><p class="muted">右键文件或文件夹可直接使用智能命名、智能归档。移动应用目录后请重新安装入口。</p><button id="install-menu">安装右键入口</button> <button id="remove-menu">移除右键入口</button>`;
  } else if (section === "文件分类") {
    content = `<form id="add-category" class="setting-form"><input id="category-name" placeholder="新分类名称" aria-label="分类名称" maxlength="40" required><button class="primary">添加分类</button></form><div class="workflow"><h3>分类设置后，请务必按一下操作。 <button id="guides" aria-label="查看操作图解">ⓘ</button></h3><div class="workflow-step"><span class="step-number">1</span><button id="copy-prompt" class="workflow-primary">复制提示词，去豆包官网</button><span id="copy-status"></span></div><div class="workflow-step"><span class="step-number">2</span><span>把提示词发给豆包，复制豆包的回复。</span></div><div class="workflow-step"><span class="step-number">3</span><button id="import-rules">录入豆包回复</button><span id="import-status"></span></div></div><div class="category-search"><span aria-hidden="true">⌕</span><input id="category-query" placeholder="搜索分类" aria-label="搜索分类"><span class="muted">${s.categories.length} 个分类</span></div><div id="category-list">${categoryList("")}</div>`;
  } else if (section === "命名规则") {
    const options = (v) =>
      ["month", "monthDay", "category"]
        .map(
          (x, i) =>
            `<option value="${x}" ${x === v ? "selected" : ""}>${["月份 + 识别的名称", "月日 + 识别的名称", "分类 + 识别的名称"][i]}</option>`,
        )
        .join("");
    content = `<div class="settings-card"><h3>文件夹命名</h3><select id="folder-format" aria-label="文件夹命名">${options(s.namingRules.folder)}</select></div><div class="settings-card"><h3>文档命名</h3><select id="document-format" aria-label="文档命名">${options(s.namingRules.document)}</select></div><div class="settings-card"><h3>日期来源</h3><select id="date-source" aria-label="日期来源"><option value="today" ${s.namingRules.dateSource === "today" ? "selected" : ""}>命名当天</option><option value="created" ${s.namingRules.dateSource === "created" ? "selected" : ""}>文件创建日期</option></select><p class="muted">日期按北京时间计算。智能命名将保留文档扩展名，更改规则后立即保存。</p></div>`;
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
  $("#check-update").onclick = async () => {
    const b = $("#check-update");
    b.disabled = true;
    try {
      let r = await api("checkUpdate");
      $("#update-status").textContent = r.message;
      if (r.url) {
        b.textContent = "立即更新";
        b.onclick = () => api("downloadUpdate");
      }
    } catch (e) {
      $("#update-status").textContent = e.message;
    } finally {
      b.disabled = false;
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
        const fallback = data.settings.categories.find((c) => c.id !== target.id && (c.id === "其他" || c.name === "其他")) || data.settings.categories.find((c) => c.id !== target.id);
        modal(`<div class="dialog-body confirm-dialog"><h2>删除分类？</h2><p>删除「${esc(target.name)}」后，其中的条目显示在「${esc(fallback?.name || "其他")}」。源文件和文件夹保留。</p>${actions("删除分类")}</div>`);
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
  let item = visibleRows.find((x) => x.path === row.dataset.file);
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
    category(visibleRows.find((x) => x.path === target.dataset.file));
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
  dragDir = e.target.closest("[data-dir]")?.dataset.dir;
  e.dataTransfer.setData("application/x-guiyu-dir", dragDir || "");
};
$("#directories").ondragover = (e) => {
  if (dragDir) e.preventDefault();
};
$("#directories").ondrop = (e) => {
  e.preventDefault();
  let target = e.target.closest("[data-dir]")?.dataset.dir,
    from = data.snapshot.directories.find((d) => d.path === dragDir),
    to = data.snapshot.directories.find((d) => d.path === target);
  dragDir = null;
  if (!from || !to || from.root !== to.root || from === to) return;
  let paths = data.snapshot.directories
    .filter((d) => d.root === from.root)
    .map((d) => d.path)
    .filter((p) => p !== from.path);
  paths.splice(paths.indexOf(to.path), 0, from.path);
  action(async () => apply(await api("order", { root: from.root, paths })));
};
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
  if ($("#modal").open || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))
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
  if (
    !["projects", "files"].includes(document.activeElement?.id) &&
    !e.target.closest(".file-row,.project-row")
  )
    return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "a") {
    e.preventDefault();
    selected = new Set(visibleRows.map((e) => e.path));
    render();
    return;
  }
  let items = selectedItems();
  if (!items.length && !source && project && e.target.id === "projects")
    items = [project];
  if (e.key === " " && items.length) {
    e.preventDefault();
    action(() => api("preview", { path: items[0].path }));
  } else if (e.key === "F2" && items.length) {
    e.preventDefault();
    namingDialog(items, false);
  } else if (e.key === "Enter" && items.length) {
    e.preventDefault();
    action(() => api("open", { path: items[0].path }));
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
    select(visibleRows[i], e);
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
