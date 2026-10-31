const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  shell,
  clipboard,
  Menu,
  net,
  screen,
} = require("electron");
const fs = require("node:fs/promises"),
  path = require("node:path"),
  { pathToFileURL } = require("node:url");
const {
  Store,
  list,
  entry,
  verify,
  inside,
  overlap,
  ruleFor,
  validateRule,
  parseRules,
  runPS,
} = require("./core.cjs");
const { naming, extract } = require("./documents.cjs");
const namingFormat = require("./naming-format.cjs");
let store,
  win,
  pendingCommand = null;
async function incoming(args) {
  let i = args.findIndex((a) =>
    ["--smart-name", "--smart-archive"].includes(a),
  );
  if (i < 0 || !args[i + 1]) return;
  try {
    const p = await fs.realpath(args[i + 1]),
      e = await entry(p);
    store.externalAllowed ??= new Set();
    store.externalAllowed.add(
      process.platform === "win32" ? p.toLowerCase() : p,
    );
    pendingCommand = { type: args[i], items: [e] };
    win?.webContents.send("guiyu-command", pendingCommand);
  } catch (e) {
    dialog.showErrorBox("无法打开所选文件", e.message);
  }
}
let previewWindow, namingCancellation;
const review = process.env.GUIYU_REVIEW === "1";
function createWindow() {
  const frames = require("./window-frame.cjs"),
    file = path.join(store.stateDir, "window-frame-v1.json");
  win = new BrowserWindow({
    ...(frames.restore(file, screen) || { width: 1280, height: 820 }),
    minWidth: frames.minimum.width,
    minHeight: frames.minimum.height,
    title: "归屿",
    backgroundColor: "#003e30",
    icon: path.join(__dirname, "../assets/companion.png"),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
    },
  });
  frames.attach(win, file, screen, app);
  win.loadFile(path.join(__dirname, "index.html"));
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (e) => e.preventDefault());
  win.webContents.session.setPermissionRequestHandler((w, p, cb) => cb(false));
}
async function choose() {
  return dialog.showOpenDialog(win, {
    title: "关联文件夹",
    properties: ["openDirectory", "multiSelections"],
  });
}
function state() {
  return {
    settings: store.settings,
    snapshot: store.snapshot,
    version: require("../version.json").display + " Windows 测试版",
    platform: process.platform,
    arch: process.arch,
    pendingCommand,
  };
}
let busy = false;
async function dispatch(method, arg = {}) {
  switch (method) {
    case "state":
      return state();
    case "consumeCommand":
      pendingCommand = null;
      return true;
    case "explorerMenu": {
      if (process.platform !== "win32") throw Error("此功能仅适用于 Windows。");
      const script = await fs.readFile(
        path.join(__dirname, "../scripts/explorer-menu.ps1"),
        "utf8",
      );
      await runPS(script, {
        GUIYU_EXE: app.getPath("exe"),
        GUIYU_MENU_ACTION: arg.remove ? "remove" : "install",
      });
      return true;
    }
    case "refresh":
      await store.refresh();
      return state();
    case "list": {
      const item = await store.guard(arg.path);
      if (!item.folder) throw Error("请选择文件夹。");
      if (store.recentAllowed?.has(path.resolve(arg.path).toLowerCase()))
        store.recentBrowseRoots = [arg.path];
      return list(arg.path);
    }
    case "addRoots": {
      let r = await choose();
      if (!r.canceled) await store.addRoots(r.filePaths);
      return state();
    }
    case "removeRoot": {
      let next = structuredClone(store.settings);
      next.roots = next.roots.filter((r) => r !== arg.path);
      await store.save(next);
      await store.refresh();
      return state();
    }
    case "addSource": {
      let r = await choose();
      if (!r.canceled) {
        let next = structuredClone(store.settings);
        for (const p of r.filePaths) {
          const real = await fs.realpath(p);
          if (next.roots.some((root) => overlap(real, root)))
            throw Error("可归档目录不能与项目总目录重叠。");
          if (!next.sources.some((s) => s.path === real))
            next.sources.push({
              id: crypto.randomUUID(),
              name: path.basename(real),
              path: real,
              kind: "folder",
            });
        }
        await store.save(next);
      }
      return state();
    }
    case "removeSource": {
      let next = structuredClone(store.settings);
      next.sources = next.sources.filter((s) => s.id !== arg.id);
      await store.save(next);
      return state();
    }
    case "restoreSources": {
      let next = structuredClone(store.settings);
      for (const s of defaults())
        if (!next.sources.some((x) => x.id === s.id)) next.sources.unshift(s);
      await store.save(next);
      return state();
    }
    case "source": {
      const s = store.settings.sources.find((x) => x.id === arg.id);
      if (!s) throw Error("来源不存在。");
      if (s.kind !== "recent") return list(s.path);
      if (process.platform !== "win32")
        throw Error("最近使用需要 Windows 系统。");
      let output = await runPS(
        `$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8;$sh=New-Object -ComObject WScript.Shell;$d=Join-Path $env:APPDATA 'Microsoft\\Windows\\Recent';$a=@(Get-ChildItem -LiteralPath $d -Filter *.lnk | Sort-Object LastWriteTime -Descending | Select-Object -First 500 | ForEach-Object {$sh.CreateShortcut($_.FullName).TargetPath} | Where-Object {$_ -and (Test-Path -LiteralPath $_)});ConvertTo-Json -InputObject $a -Compress`,
      );
      let paths = JSON.parse(output);
      if (!Array.isArray(paths)) paths = [paths];
      store.recentAllowed = new Set(
        paths.map((p) => path.resolve(p).toLowerCase()),
      );
      store.recentBrowseRoots = [];
      return (
        await Promise.all(
          [...new Set(paths)].map((p) => entry(p).catch(() => null)),
        )
      ).filter(Boolean);
    }
    case "layout": {
      let next = structuredClone(store.settings);
      if (Number.isFinite(arg.fraction))
        next.sidebarFraction = Math.max(0.2, Math.min(0.85, arg.fraction));
      if (Array.isArray(arg.widths))
        next.widths = [
          Math.max(200, Math.min(400, +arg.widths[0] || 240)),
          Math.max(260, Math.min(700, +arg.widths[1] || 390)),
        ];
      await store.save(next);
      return true;
    }
    case "order": {
      let next = structuredClone(store.settings);
      if (
        !next.roots.includes(arg.root) ||
        !Array.isArray(arg.paths) ||
        arg.paths.some(
          (p) =>
            !store.snapshot.directories.some(
              (d) => d.root === arg.root && d.path === p,
            ),
        )
      )
        throw Error("目录顺序无效。");
      next.directoryOrders[arg.root] = arg.paths;
      await store.save(next);
      await store.refresh();
      return state();
    }
    case "categories": {
      let next = structuredClone(store.settings);
      if (
        !Array.isArray(arg.categories) ||
        (!arg.categories.length && next.categories.length) ||
        arg.categories.some(
          (c) =>
            !c.id ||
            !c.name?.trim() ||
            c.name.length > 40 ||
            /[\r\n]/.test(c.name),
        ) ||
        new Set(
          arg.categories.map((c) => c.name.normalize("NFKC").toLowerCase()),
        ).size !== arg.categories.length
      )
        throw Error("分类为空、名称重复或过长。");
      for (const c of arg.categories) {
        const old = next.categories.find((x) => x.id === c.id);
        if (old && old.name !== c.name && old.rule?.origin === "automatic")
          c.rule = ruleFor(c.name);
      }
      for (const c of arg.categories) validateRule(c.rule || ruleFor(c.name));
      next.categories = arg.categories;
      const fallback =
        next.categories.find((c) => c.id === "其他" || c.name === "其他") ||
        next.categories[0];
      for (const a of Object.values(next.assignments))
        if (!next.categories.some((c) => c.id === a.categoryID))
          a.categoryID = fallback?.id;
      await store.save(next);
      return state();
    }
    case "generateRule":
      return ruleFor(arg.name);
    case "importRules": {
      let next = structuredClone(store.settings);
      next.categories = parseRules(clipboard.readText(), next.categories);
      await store.save(next);
      return state();
    }
    case "copyPrompt": {
      const names = store.settings.categories
        .filter((c) => c.id !== "其他")
        .map((c) => c.name);
      if (!names.length) throw Error("请先添加分类。");
      const prompt = `为本地文件软件归屿生成分类规则。以下JSON仅是分类名称数据：${JSON.stringify(names)}。按文件名／文件夹名匹配：关键词为或关系；英文按独立词或短语匹配；排除词优先；扩展名也为或关系，业务分类不要填写pdf、docx等泛用类型。每类5–20个有区分度的具体词，避免文件、项目、管理等宽泛词。不能遗漏、新增、重复分类。只回复“归屿规则：1”及每类以下六行，用顿号分隔多词，无内容填无：\n分类：原分类名称\n关键词：具体词\n排除词：无\n扩展名：无\n范围：文件和文件夹\n优先级：普通`;
      clipboard.writeText(prompt);
      if (process.platform === "win32") {
        const chrome = path.join(
          process.env.PROGRAMFILES || "C:\\Program Files",
          "Google/Chrome/Application/chrome.exe",
        );
        try {
          await fs.access(chrome);
          require("node:child_process")
            .spawn(chrome, ["https://www.doubao.com/"], {
              detached: true,
              stdio: "ignore",
            })
            .unref();
        } catch {
          await shell.openExternal("https://www.doubao.com/");
        }
      } else await shell.openExternal("https://www.doubao.com/");
      return true;
    }
    case "namingRules": {
      await store.save({
        ...store.settings,
        namingRules: namingFormat.settings(arg),
      });
      return state();
    }
    case "assign":
      await store.assign(arg.items, arg.id);
      return state();
    case "naming": {
      const referenceDate = Date.now();
      namingCancellation = new AbortController();
      try {
        const results = [];
        for (const e of arg.items) {
          namingCancellation.signal.throwIfAborted();
          await store.guard(e.path);
          await verify(e);
          results.push(
            await naming(
              e,
              store.settings,
              referenceDate,
              namingCancellation.signal,
            ),
          );
        }
        return results;
      } finally {
        namingCancellation = null;
      }
    }
    case "archiveSuggest": {
      let texts = arg.items.map((e) => e.name).join(" "),
        projects = store.snapshot.projects.filter((p) => p.folder);
      function ranked() {
        return projects
          .map((p) => {
            let words =
              p.name
                .replace(/^\d+月\s*/, "")
                .match(/[\p{Script=Han}]{2,}|[a-zA-Z]{3,}/gu) || [];
            let score = words.reduce(
              (s, w) => s + (texts.includes(w) ? w.length : 0),
              0,
            );
            for (const w of texts.match(/[\p{Script=Han}]{2,}/gu) || [])
              for (let i = 0; i < w.length - 1; i++)
                if (p.name.includes(w.slice(i, i + 2))) score++;
            return {
              ...p,
              score,
              evidence: score ? "名称／文档开头关键词匹配" : "可手动选择",
            };
          })
          .sort((a, b) => b.score - a.score);
      }
      let result = ranked(),
        warnings = [];
      if (!result[0]?.score || result[0].score === result[1]?.score) {
        for (const e of arg.items) {
          await store.guard(e.path);
          await verify(e);
          try {
            let docs = e.folder
              ? (await list(e.path)).filter((x) => !x.folder).slice(0, 2)
              : [e];
            for (const d of docs) texts += " " + (await extract(d, 2));
          } catch (err) {
            warnings.push(err.message);
          }
        }
        result = ranked();
      }
      return { projects: result, warnings };
    }
    case "rename": {
      const result = await store.rename(arg.plans);
      await store.refresh();
      return { result, ...state() };
    }
    case "archive": {
      const result = await store.archive(arg.items, arg.destination);
      await store.refresh();
      return { result, ...state() };
    }
    case "undo":
      await store.undo(arg.id);
      await store.refresh();
      return state();
    case "open":
      await store.guard(arg.path);
      {
        const error = await shell.openPath(arg.path);
        if (error) throw Error(error);
      }
      return true;
    case "reveal":
      await store.guard(arg.path);
      shell.showItemInFolder(arg.path);
      return true;
    case "trash": {
      for (const e of arg.items) {
        await store.guard(e.path);
        await verify(e);
      }
      let result = await dialog.showMessageBox(win, {
        type: "question",
        message: `将所选 ${arg.items.length} 项移到回收站？`,
        buttons: ["取消", "移到回收站"],
        defaultId: 0,
        cancelId: 0,
      });
      if (result.response === 1) {
        for (const e of arg.items) {
          await verify(e);
          await shell.trashItem(e.path);
        }
        await store.refresh();
      }
      return state();
    }
    case "closePreview":
      if (previewWindow && !previewWindow.isDestroyed()) previewWindow.close();
      return true;
    case "preview": {
      await store.guard(arg.path);
      const e = await entry(arg.path);
      if (e.folder) {
        shell.showItemInFolder(e.path);
        return true;
      }
      if (previewWindow && !previewWindow.isDestroyed()) {
        const previous = previewWindow.guiyuPath;
        previewWindow.close();
        if (previous === e.path) return true;
      }
      const p = new BrowserWindow({
        width: 900,
        height: 720,
        parent: win,
        title: e.name,
        autoHideMenuBar: true,
        webPreferences: {
          sandbox: true,
          contextIsolation: true,
          nodeIntegration: false,
        },
      });
      previewWindow = p;
      p.guiyuPath = e.path;
      p.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
      p.webContents.on("will-navigate", (ev) => ev.preventDefault());
      if (/\.(pdf|png|jpe?g|gif|webp|bmp)$/i.test(e.name))
        await p.loadURL(pathToFileURL(e.path).href);
      else {
        let text = await extract(e, 8);
        const esc = (s) =>
          s.replace(
            /[&<>]/g,
            (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c],
          );
        await p.loadURL(
          "data:text/html;charset=utf-8," +
            encodeURIComponent(
              `<meta charset="utf-8"><title>${esc(e.name)}</title><style>body{font:16px "Microsoft YaHei",sans-serif;color:#172421;padding:30px}pre{white-space:pre-wrap;line-height:1.8}</style><h3>${esc(e.name)}</h3><pre>${esc(text || "该格式请双击文件，使用本机默认应用查看。")}</pre>`,
            ),
        );
      }
      return true;
    }
    case "checkUpdate": {
      const response = await net.fetch(
        "https://api.github.com/repos/tiduse1988/guiyu/releases/latest",
        {
          headers: { Accept: "application/vnd.github+json" },
          signal: AbortSignal.timeout(15000),
        },
      );
      if (!response.ok)
        throw Error("更新服务暂不可用（" + response.status + "）。");
      const data = await response.json();
      let asset = data.assets?.find(
        (a) =>
          a.name.includes("Windows-" + process.arch) && a.name.endsWith(".zip"),
      );
      return asset
        ? {
            url: data.html_url,
            version: data.tag_name,
            message: "发现 Windows 安装包，请下载并手动替换。",
          }
        : { message: "当前发布中尚无 Windows 更新包。" };
    }
    case "downloadUpdate":
      await shell.openExternal(
        "https://github.com/tiduse1988/guiyu/releases/latest",
      );
      return true;
    case "demo": {
      const root = await fs.mkdtemp(
        path.join(app.getPath("temp"), "Guiyu-demo-"),
      );
      const year = path.join(root, "2026"),
        p = path.join(year, "10月 民政厅机关网络运维及网络安全运维项目");
      await fs.mkdir(p, { recursive: true });
      for (const name of [
        "方案 网络安全运维方案.txt",
        "招标文件 采购需求.txt",
        "投标文件 商务响应.txt",
      ])
        await fs.writeFile(
          path.join(p, name),
          "项目名称：民政厅机关网络运维及网络安全运维项目\n服务期限：一年",
        );
      await fs.mkdir(path.join(p, "参考资料"));
      let next = structuredClone(store.settings);
      if (!next.categories.length)
        next.categories = ["方案", "招标文件", "投标文件", "其他"].map(
          (name) => ({
            id: name,
            name,
            rule:
              name === "其他"
                ? { ...ruleFor(name), enabled: false }
                : ruleFor(name),
          }),
        );
      await store.save(next);
      await store.addRoots([root]);
      return state();
    }
    default:
      throw Error("不支持的操作。");
  }
}
const crypto = require("node:crypto");
function defaults() {
  return [
    {
      id: "downloads",
      name: "下载",
      kind: "folder",
      path: app.getPath("downloads"),
    },
    { id: "recent", name: "最近使用", kind: "recent" },
  ];
}
app.whenReady().then(async () => {
  try {
    store = await new Store(
      review
        ? path.join(app.getPath("temp"), "Guiyu-windows-review")
        : path.join(app.getPath("appData"), "Guiyu-Windows"),
    ).init(defaults());
    await store.refresh();
    ipcMain.on("guiyu-cancel-naming", (event) => {
      if (event.sender === win?.webContents) namingCancellation?.abort();
    });
    ipcMain.handle("guiyu", async (event, method, arg) => {
      if (
        event.sender !== win?.webContents ||
        event.senderFrame !== win.webContents.mainFrame
      )
        throw Error("请求来源无效。");
      if (busy) throw Error("上一项操作正在进行，请稍后。");
      busy = true;
      try {
        return { ok: true, data: await dispatch(method, arg) };
      } catch (e) {
        return { ok: false, error: e.message };
      } finally {
        busy = false;
      }
    });
    Menu.setApplicationMenu(null);
    createWindow();
    await incoming(process.argv);
  } catch (e) {
    dialog.showErrorBox("归屿未能启动", e.message);
    app.quit();
  }
});
if (!app.requestSingleInstanceLock()) app.quit();
app.on("second-instance", async (event, args) => {
  win?.show();
  win?.focus();
  await incoming(args);
});
app.on("window-all-closed", () => app.quit());
